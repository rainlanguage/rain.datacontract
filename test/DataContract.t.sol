// SPDX-License-Identifier: CAL
pragma solidity ^0.8.13;

import "qakit.foundry/QAKitMemoryTest.sol";
import "../src/DataContract.sol";

contract DataContractTest is QAKitMemoryTest {

    function assertMemoryAlignment() internal {
        // Check alignment of memory after allocation.
        uint256 memPtr_;
        assembly ("memory-safe") {
            memPtr_ := mload(0x40)
        }
        assertEq(memPtr_ % 0x20, 0);
    }

    /// Solidity manages memory in the following way. There is a “free memory pointer” at position 0x40 in memory.
    /// If you want to allocate memory, use the memory starting from where this pointer points at and update it.
    /// **There is no guarantee that the memory has not been used before and thus you cannot assume that its contents are zero bytes.**
    function copyPastAllocatedMemory(bytes memory data_) internal pure {
        uint256 outputCursor_;
        uint256 inputCursor_;
        assembly {
            inputCursor_ := data_
            outputCursor_ := mload(0x40)
        }
        unsafeCopyBytesTo(inputCursor_, outputCursor_, data_.length);
    }

    function testRoundFuzz(bytes memory data_, bytes memory garbage_) public {
        copyPastAllocatedMemory(garbage_);
        assertMemoryAlignment();
        (DataContractMemoryContainer container_, uint256 outputCursor_) = DataContract.newContainer(data_.length);
        assertMemoryAlignment();

        uint256 inputCursor_;
        assembly ("memory-safe") {
            inputCursor_ := add(data_, 0x20)
        }
        unsafeCopyBytesTo(inputCursor_, outputCursor_, data_.length);
        assertMemoryAlignment();

        address pointer_ = DataContract.write(container_);
        assertMemoryAlignment();

        bytes memory round_ = DataContract.read(pointer_);
        assertMemoryAlignment();

        assertEq(round_.length, data_.length);
        assertEq(round_, data_);
    }

    function testRoundZero() public {
        testRoundFuzz(hex"00", "");
    }

    function testRoundOne() public {
        testRoundFuzz(hex"01", "");
    }

    function testRoundEmpty() public {
        testRoundFuzz("", "");
    }

    function testRoundGarbage() public {
        // Fuzzer picked this up.
        testRoundFuzz("", hex"020000000000000000000000000000000000000000000000000000000000000000");
    }

    function testErrorBadAddressRead() public {
        vm.expectRevert(ReadError.selector);
        DataContract.read(address(5));
    }
}
