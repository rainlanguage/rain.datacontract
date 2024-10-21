// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 thedavidmeister
pragma solidity =0.8.25;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {LibMemCpy} from "../../lib/rain.solmem/src/lib/LibMemCpy.sol";
import {LibMemory} from "../../lib/rain.solmem/src/lib/LibMemory.sol";
import {LibBytes} from "../../lib/rain.solmem/src/lib/LibBytes.sol";

import {
    LibPointer,
    Pointer,
    DataContractMemoryContainer,
    LibDataContract,
    ReadError
} from "../../src/lib/LibDataContract.sol";

/// @title DataContractTest
/// Tests for serializing and deserializing data to and from an onchain data
/// contract.
contract DataContractTest is Test {
    using LibBytes for bytes;
    using LibPointer for Pointer;

    /// Writing any data to a contract then reading it back without corrupting
    /// memory or the data itself.
    function testRoundFuzz(bytes memory data, bytes memory garbage) public {
        // Put some garbage in unallocated memory.
        LibMemCpy.unsafeCopyBytesTo(garbage.dataPointer(), LibPointer.allocatedMemoryPointer(), garbage.length);

        assertTrue(LibMemory.memoryIsAligned());
        (DataContractMemoryContainer container, Pointer pointer) = LibDataContract.newContainer(data.length);
        assertTrue(LibMemory.memoryIsAligned());

        LibMemCpy.unsafeCopyBytesTo(data.dataPointer(), pointer, data.length);
        assertTrue(LibMemory.memoryIsAligned());

        address datacontract = LibDataContract.write(container);
        assertTrue(LibMemory.memoryIsAligned());

        bytes memory round = LibDataContract.read(datacontract);
        assertTrue(LibMemory.memoryIsAligned());

        assertEq(round.length, data.length);
        assertEq(round, data);
    }

    /// Reading from a contract that isn't a valid data contract should throw
    /// a ReadError.
    function testErrorBadAddressRead(address a) public {
        vm.expectRevert(ReadError.selector);
        //slither-disable-next-line unused-return
        LibDataContract.read(
            address(
                uint160(
                    uint256(
                        // Hash the input because the fuzzer passes in addresses that it has
                        // seen elsewhere in the test suite, which can include previously
                        // deployed contracts.
                        keccak256(abi.encodePacked(a))
                    )
                )
            )
        );
    }

    /// Should be possible to read only a slice of the data.
    function testRoundSlice(bytes memory data, uint16 start, uint16 length) public {
        vm.assume(uint256(start) + uint256(length) <= data.length);

        bytes memory expected = new bytes(length);
        LibMemCpy.unsafeCopyBytesTo(data.dataPointer().unsafeAddBytes(start), expected.dataPointer(), length);

        (DataContractMemoryContainer container, Pointer pointer) = LibDataContract.newContainer(data.length);
        LibMemCpy.unsafeCopyBytesTo(data.dataPointer(), pointer, data.length);
        address datacontract = LibDataContract.write(container);

        bytes memory slice = LibDataContract.readSlice(datacontract, start, length);

        assertEq(expected, slice);
    }

    /// Reading a slice that is out of bounds should throw a ReadError.
    function testRoundSliceError(bytes memory data, uint16 start, uint16 length) public {
        vm.assume(uint256(start) + uint256(length) > data.length);

        (DataContractMemoryContainer container, Pointer pointer) = LibDataContract.newContainer(data.length);
        LibMemCpy.unsafeCopyBytesTo(data.dataPointer(), pointer, data.length);
        address datacontract_ = LibDataContract.write(container);

        vm.expectRevert(ReadError.selector);
        //slither-disable-next-line unused-return
        LibDataContract.readSlice(datacontract_, start, length);
    }

    /// Reading a slice over the whole contract gives the same result as reading
    /// the whole contract.
    function testSameReads(bytes memory data) public {
        (DataContractMemoryContainer container, Pointer pointer) = LibDataContract.newContainer(data.length);
        LibMemCpy.unsafeCopyBytesTo(data.dataPointer(), pointer, data.length);
        address datacontract = LibDataContract.write(container);

        uint256 a = gasleft();
        bytes memory read = LibDataContract.read(datacontract);
        uint256 b = gasleft();
        bytes memory readSlice = LibDataContract.readSlice(datacontract, 0, uint16(data.length));
        uint256 c = gasleft();

        assertEq(read, readSlice);
        // normal read should be cheaper than a slice otherwise what's the point?
        assertGt(b - c, a - b);
    }

    /// Writing data twice yields two different addresses even if the data is
    /// the same.
    function testNewAddressFuzzData(bytes memory data) public {
        (DataContractMemoryContainer container, Pointer pointer) = LibDataContract.newContainer(data.length);
        LibMemCpy.unsafeCopyBytesTo(data.dataPointer(), pointer, data.length);

        address datacontractAlpha = LibDataContract.write(container);
        address datacontractBeta = LibDataContract.write(container);

        assertTrue(datacontractAlpha != datacontractBeta);
        assertEq(LibDataContract.read(datacontractAlpha), LibDataContract.read(datacontractBeta));
    }

    /// Writing data twice yields two different addresses if the data is
    /// different.
    function testNewAddressFuzzDataDifferent(bytes memory alpha, bytes memory beta) public {
        vm.assume(keccak256(alpha) != keccak256(beta));
        (DataContractMemoryContainer containerAlpha, Pointer pointerAlpha) = LibDataContract.newContainer(alpha.length);
        LibMemCpy.unsafeCopyBytesTo(alpha.dataPointer(), pointerAlpha, alpha.length);
        (DataContractMemoryContainer containerBeta, Pointer pointerBeta) = LibDataContract.newContainer(beta.length);
        LibMemCpy.unsafeCopyBytesTo(beta.dataPointer(), pointerBeta, beta.length);

        address datacontractAlpha = LibDataContract.write(containerAlpha);
        address datacontractBeta = LibDataContract.write(containerBeta);

        assertTrue(datacontractAlpha != datacontractBeta);
        assertTrue(
            keccak256(LibDataContract.read(datacontractAlpha)) != keccak256(LibDataContract.read(datacontractBeta))
        );
    }

    /// Check there is always a 0 byte prefix on the underlying data contract.
    function testZeroPrefix(bytes memory data) public {
        (DataContractMemoryContainer container, Pointer pointer) = LibDataContract.newContainer(data.length);
        LibMemCpy.unsafeCopyBytesTo(data.dataPointer(), pointer, data.length);
        address datacontract_ = LibDataContract.write(container);
        uint256 firstByte;
        assembly ("memory-safe") {
            mstore(0, 0)
            // copy to scratch.
            extcodecopy(datacontract_, 0, 0, 1)
            firstByte := mload(0)
        }
        assertEq(firstByte, 0);
    }

    /// Check that if we deploy with zoltu we get the same address on different
    /// networks.
    function testZoltu() public {
        bytes memory data = bytes("zoltu");

        (DataContractMemoryContainer container, Pointer pointer) = LibDataContract.newContainer(data.length);
        LibMemCpy.unsafeCopyBytesTo(data.dataPointer(), pointer, data.length);

        vm.createSelectFork(vm.envString("CI_FORK_ETH_RPC_URL"));

        address datacontractAlpha = LibDataContract.writeZoltu(container);

        assertEq(datacontractAlpha, 0x7B5220368D7460A84bCFCCB0616f77E61e5302e2);
        assertEq(keccak256(data), keccak256(LibDataContract.read(datacontractAlpha)));

        vm.createSelectFork(vm.envString("CI_FORK_AVALANCHE_RPC_URL"));

        address datacontractBeta = LibDataContract.writeZoltu(container);

        assertEq(datacontractBeta, 0x7B5220368D7460A84bCFCCB0616f77E61e5302e2);
        assertEq(keccak256(data), keccak256(LibDataContract.read(datacontractBeta)));
    }
}
