// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {LibMemCpy} from "rain.solmem/lib/LibMemCpy.sol";
import {LibBytes} from "rain.solmem/lib/LibBytes.sol";

import {
    LibPointer,
    Pointer,
    DataContractMemoryContainer,
    LibDataContract,
    ReadError,
    WriteError,
    ZOLTU_PROXY_ADDRESS
} from "src/lib/LibDataContract.sol";

/// @title DataContractTest
/// Tests for serializing and deserializing data to and from an onchain data
/// contract.
contract DataContractTest is Test {
    using LibBytes for bytes;
    using LibPointer for Pointer;

    function contractCreationCodeVeryLargeData(uint256 length) external pure {
        bytes memory data;
        // Point data after allocated memory and just extend it virtually out
        // to the desired length without doing an explicit memory expansion.
        assembly ("memory-safe") {
            data := mload(0x40)
            mstore(data, length)
        }
        LibDataContract.contractCreationCode(data);
    }

    function testContractCreationCodeDataTooLargeRevert(uint256 length) external {
        length = bound(length, uint256(type(uint16).max) + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(LibDataContract.DataTooLarge.selector, length));
        this.contractCreationCodeVeryLargeData(length);
    }

    function readExternal(address datacontract) external view returns (bytes memory) {
        return LibDataContract.read(datacontract);
    }

    function readSliceExternal(address datacontract, uint16 start, uint16 length) external view returns (bytes memory) {
        return LibDataContract.readSlice(datacontract, start, length);
    }

    function testRoundCreationCodeFuzz(bytes memory data, bytes memory garbage, uint16 start, uint16 sliceLength)
        external
    {
        bytes32 dataHash = keccak256(data);
        vm.assume(uint256(start) + uint256(sliceLength) <= data.length);

        bytes memory expectedSlice = new bytes(sliceLength);
        LibMemCpy.unsafeCopyBytesTo(data.dataPointer().unsafeAddBytes(start), expectedSlice.dataPointer(), sliceLength);

        // Put some garbage in unallocated memory.
        LibMemCpy.unsafeCopyBytesTo(garbage.dataPointer(), LibPointer.allocatedMemoryPointer(), garbage.length);

        bytes memory creationCode = LibDataContract.contractCreationCode(data);
        address dataContract;
        assembly ("memory-safe") {
            dataContract := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        bytes memory round = LibDataContract.read(dataContract);

        assertEq(round.length, data.length);
        assertEq(round, data);

        // Check before/after hashes against datas to ensure bad mutations didn't
        // occur somewhere in the process.
        assertEq(keccak256(data), dataHash);
        assertEq(keccak256(round), dataHash);

        bytes memory roundSlice = LibDataContract.readSlice(dataContract, start, sliceLength);
        assertEq(roundSlice, expectedSlice);
    }

    /// Reading from a contract that isn't a valid data contract should throw
    /// a ReadError.
    function testErrorBadAddressRead(address a) public {
        vm.expectRevert(ReadError.selector);
        (bytes memory read) = this.readExternal(
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
        (read);
    }

    /// Reading a slice that is out of bounds should throw a ReadError.
    function testRoundSliceError(bytes memory data, uint16 start, uint16 length) public {
        vm.assume(uint256(start) + uint256(length) > data.length);

        bytes memory creationCode = LibDataContract.contractCreationCode(data);
        address dataContract;
        assembly ("memory-safe") {
            dataContract := create(0, add(creationCode, 0x20), mload(creationCode))
        }

        vm.expectRevert(ReadError.selector);
        (bytes memory slice) = this.readSliceExternal(dataContract, start, length);
        (slice);
    }

    /// Reading a slice over the whole contract gives the same result as reading
    /// the whole contract.
    function testSameReads(bytes memory data) public {
        bytes memory creationCode = LibDataContract.contractCreationCode(data);
        address dataContract;
        assembly ("memory-safe") {
            dataContract := create(0, add(creationCode, 0x20), mload(creationCode))
        }

        uint256 a = gasleft();
        bytes memory read = LibDataContract.read(dataContract);
        uint256 b = gasleft();
        bytes memory readSlice = LibDataContract.readSlice(dataContract, 0, uint16(data.length));
        uint256 c = gasleft();

        assertEq(read, readSlice);
        // normal read should be cheaper than a slice otherwise what's the point?
        assertGt(b - c, a - b);
    }

    /// Check there is always a 0 byte prefix on the underlying data contract.
    function testZeroPrefix(bytes memory data) public {
        bytes memory creationCode = LibDataContract.contractCreationCode(data);
        address dataContract;
        assembly ("memory-safe") {
            dataContract := create(0, add(creationCode, 0x20), mload(creationCode))
        }

        uint256 firstByte;
        assembly ("memory-safe") {
            mstore(0, 0)
            // copy to scratch.
            extcodecopy(dataContract, 0, 0, 1)
            firstByte := mload(0)
        }
        assertEq(firstByte, 0);
    }
}
