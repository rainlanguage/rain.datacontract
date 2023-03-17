// SPDX-License-Identifier: CAL
pragma solidity ^0.8.16;

import "qakit.foundry/QAKitMemoryTest.sol";
import "sol.lib.bytes/LibBytes.sol";
import "../src/LibDataContract.sol";

contract DataContractTest is QAKitMemoryTest {
    using LibBytes for bytes;

    function testRoundFuzz(bytes memory data_, bytes memory garbage_) public {
        copyPastAllocatedMemory(garbage_);
        assertMemoryAlignment();
        (DataContractMemoryContainer container_, Cursor outputCursor_) = LibDataContract.newContainer(data_.length);
        assertMemoryAlignment();

        LibBytes.unsafeCopyBytesTo(data_.cursor(), outputCursor_, data_.length);
        assertMemoryAlignment();

        address pointer_ = LibDataContract.write(container_);
        assertMemoryAlignment();

        bytes memory round_ = LibDataContract.read(pointer_);
        assertMemoryAlignment();

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
        LibBytes.unsafeCopyBytesTo(Cursor.wrap(Cursor.unwrap(data_.cursor()) + start_), expected_.cursor(), length_);

        (DataContractMemoryContainer container_, Cursor outputCursor_) = LibDataContract.newContainer(data_.length);
        LibBytes.unsafeCopyBytesTo(data_.cursor(), outputCursor_, data_.length);
        address pointer_ = LibDataContract.write(container_);

        bytes memory slice_ = LibDataContract.readSlice(pointer_, start_, length_);

        assertEq(expected_, slice_);
    }

    function testRoundSliceError(bytes memory data_, uint16 start_, uint16 length_) public {
        vm.assume(uint256(start_) + uint256(length_) > data_.length);

        (DataContractMemoryContainer container_, Cursor outputCursor_) = LibDataContract.newContainer(data_.length);
        LibBytes.unsafeCopyBytesTo(data_.cursor(), outputCursor_, data_.length);
        address pointer_ = LibDataContract.write(container_);

        vm.expectRevert(ReadError.selector);
        //slither-disable-next-line unused-return
        LibDataContract.readSlice(pointer_, start_, length_);
    }

    function testSameReads(bytes memory data_) public {
        (DataContractMemoryContainer container_, Cursor outputCursor_) = LibDataContract.newContainer(data_.length);
        LibBytes.unsafeCopyBytesTo(data_.cursor(), outputCursor_, data_.length);
        address pointer_ = LibDataContract.write(container_);

        assertEq(LibDataContract.read(pointer_), LibDataContract.readSlice(pointer_, 0, uint16(data_.length)));
    }
}
