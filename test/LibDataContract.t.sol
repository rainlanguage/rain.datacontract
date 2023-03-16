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
        //slither-disable-next-line unused-return
        LibDataContract.read(address(5));
    }
}
