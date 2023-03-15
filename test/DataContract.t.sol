// SPDX-License-Identifier: CAL
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/DataContract.sol";

contract DataContractTest is Test {
    function testRound() public {
        (bytes memory container_, uint256 cursor_) = DataContract.allocate(0x20);
        assembly ("memory-safe") {
            mstore(cursor_, 1)
        }
        address pointer_ = DataContract.write(container_);
        bytes memory round_ = DataContract.read(pointer_);

        assertEq(round_.length, 0x20);
        assertEq(uint256(bytes32(round_)), 1);
    }
}
