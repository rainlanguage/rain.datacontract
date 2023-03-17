// SPDX-License-Identifier: CAL
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "qakit.foundry/LibQAKitMemory.sol";
import "sol.lib.memory/LibMemory.sol";
import "../src/LibDataContract.sol";

contract DataContractTest is Test {
    using LibMemory for bytes;
    using LibMemory for Pointer;

    function testRoundFuzz(bytes memory data_, bytes memory garbage_) public {
        LibQAKitMemory.copyPastAllocatedMemory(garbage_);
        assertTrue(LibQAKitMemory.memoryIsAligned());
        (DataContractMemoryContainer container_, Pointer pointer_) = LibDataContract.newContainer(data_.length);
        assertTrue(LibQAKitMemory.memoryIsAligned());

        LibMemory.unsafeCopyBytesTo(data_.dataPointer(), pointer_, data_.length);
        assertTrue(LibQAKitMemory.memoryIsAligned());

        address datacontract_ = LibDataContract.write(container_);
        assertTrue(LibQAKitMemory.memoryIsAligned());

        bytes memory round_ = LibDataContract.read(datacontract_);
        assertTrue(LibQAKitMemory.memoryIsAligned());

        assertEq(round_.length, data_.length);
        assertEq(round_, data_);
    }

    function testErrorBadAddressRead(address a_) public {
        vm.expectRevert(ReadError.selector);
        //slither-disable-next-line unused-return
        LibDataContract.read(
            address(
                uint160(
                    uint256(
                        // Hash the input because the fuzzer passes in addresses that it has
                        // seen elsewhere in the test suite, which can include previously
                        // deployed contracts.
                        keccak256(abi.encodePacked(a_))
                    )
                )
            )
        );
    }

    function testRoundSlice(bytes memory data_, uint16 start_, uint16 length_) public {
        vm.assume(uint256(start_) + uint256(length_) <= data_.length);

        bytes memory expected_ = new bytes(length_);
        LibMemory.unsafeCopyBytesTo(data_.dataPointer().addBytes(start_), expected_.dataPointer(), length_);

        (DataContractMemoryContainer container_, Pointer pointer_) = LibDataContract.newContainer(data_.length);
        LibMemory.unsafeCopyBytesTo(data_.dataPointer(), pointer_, data_.length);
        address datacontract_ = LibDataContract.write(container_);

        bytes memory slice_ = LibDataContract.readSlice(datacontract_, start_, length_);

        assertEq(expected_, slice_);
    }

    function testRoundSliceError(bytes memory data_, uint16 start_, uint16 length_) public {
        vm.assume(uint256(start_) + uint256(length_) > data_.length);

        (DataContractMemoryContainer container_, Pointer pointer_) = LibDataContract.newContainer(data_.length);
        LibMemory.unsafeCopyBytesTo(data_.dataPointer(), pointer_, data_.length);
        address datacontract_ = LibDataContract.write(container_);

        vm.expectRevert(ReadError.selector);
        //slither-disable-next-line unused-return
        LibDataContract.readSlice(datacontract_, start_, length_);
    }

    function testSameReads(bytes memory data_) public {
        (DataContractMemoryContainer container_, Pointer pointer_) = LibDataContract.newContainer(data_.length);
        LibMemory.unsafeCopyBytesTo(data_.dataPointer(), pointer_, data_.length);
        address datacontract_ = LibDataContract.write(container_);

        uint256 a_ = gasleft();
        bytes memory read_ = LibDataContract.read(datacontract_);
        uint256 b_ = gasleft();
        bytes memory readSlice_ = LibDataContract.readSlice(datacontract_, 0, uint16(data_.length));
        uint256 c_ = gasleft();

        assertEq(read_, readSlice_);
        // normal read should be cheaper than a slice otherwise what's the point?
        assertGt(b_ - c_, a_ - b_);
    }

    function testNewAddressFuzzData(bytes memory data_) public {
        (DataContractMemoryContainer container_, Pointer pointer_) = LibDataContract.newContainer(data_.length);
        LibMemory.unsafeCopyBytesTo(data_.dataPointer(), pointer_, data_.length);
        address datacontract0_ = LibDataContract.write(container_);
        address datacontract1_ = LibDataContract.write(container_);

        assertTrue(datacontract0_ != datacontract1_);
        assertEq(LibDataContract.read(datacontract0_), LibDataContract.read(datacontract1_));
    }

    function testNewAddressFixedData() public {
        testNewAddressFuzzData(hex"f000");
    }

    function testZeroPrefix(bytes memory data_) public {
        (DataContractMemoryContainer container_, Pointer pointer_) = LibDataContract.newContainer(data_.length);
        LibMemory.unsafeCopyBytesTo(data_.dataPointer(), pointer_, data_.length);
        address datacontract_ = LibDataContract.write(container_);
        uint256 firstByte_;
        assembly ("memory-safe") {
            // copy to scratch.
            extcodecopy(datacontract_, 0, 0, 1)
            firstByte_ := mload(0)
        }
        assertEq(firstByte_, 0);
    }
}
