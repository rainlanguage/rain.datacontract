// SPDX-License-Identifier: CAL
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/DataContract.sol";

contract DataContractTest is Test {
    function unsafeCopyBytesTo(uint256 inputCursor_, uint256 outputCursor_, uint256 remaining_) internal pure {
        assembly ("memory-safe") {
            for {} iszero(lt(remaining_, 0x20)) {
                remaining_ := sub(remaining_, 0x20)
                inputCursor_ := add(inputCursor_, 0x20)
                outputCursor_ := add(outputCursor_, 0x20)
            } { mstore(outputCursor_, mload(inputCursor_)) }

            if gt(remaining_, 0) {
                // Slither false positive here due to the variable shift of a
                // constant value to create a mask.
                let mask_ := shr(mul(remaining_, 8), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                // preserve existing bytes
                mstore(
                    outputCursor_,
                    or(
                        // input
                        and(mload(inputCursor_), not(mask_)),
                        and(mload(outputCursor_), mask_)
                    )
                )
            }
        }
    }

    function assertMemoryAlignment() internal {
        // Check alignment of memory after allocation.
        uint256 memPtr_;
        assembly ("memory-safe") {
            memPtr_ := mload(0x40)
        }
        assertEq(memPtr_ % 0x20, 0);
    }

    function testRoundFuzz(bytes memory data_) public {
        assertMemoryAlignment();
        (uint256 container_, uint256 outputCursor_) = DataContract.allocate(data_.length);
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
        testRoundFuzz(hex"00");
    }

    function testRoundOne() public {
        testRoundFuzz(hex"01");
    }

    function testRoundEmpty() public {
        testRoundFuzz("");
    }
}
