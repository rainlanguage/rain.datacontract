// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibDataContract, ReadError} from "src/lib/LibDataContract.sol";

/// @title LibDataContractTest
/// Tests that `readSlice` masks its `uint16` parameters where they enter
/// assembly: bits above the low 16 of the `start` and `length` stack words
/// must not influence the bounds check, the memory allocation, or the copied
/// data.
contract LibDataContractTest is Test {
    /// Deploy a data contract from `data` and return its address.
    function deploy(bytes memory data) internal returns (address dataContract) {
        bytes memory creationCode = LibDataContract.contractCreationCode(data);
        assembly ("memory-safe") {
            dataContract := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        assertTrue(dataContract != address(0));
    }

    /// Calls `readSlice` with `start` and `length` stack words carrying the
    /// full 256 bits of the given values, bypassing the cleanup Solidity
    /// performs on ABI-decoded values. `readSlice` must behave as though only
    /// the low 16 bits were passed.
    function readSliceDirty(address pointer, uint256 dirtyStart, uint256 dirtyLength)
        external
        view
        returns (bytes memory)
    {
        uint16 start;
        uint16 length;
        assembly ("memory-safe") {
            start := dirtyStart
            length := dirtyLength
        }
        return LibDataContract.readSlice(pointer, start, length);
    }

    /// Dirty bits above uint16 in `start` and `length` MUST NOT change the
    /// slice: the result equals the clean call on the low 16 bits. Without
    /// masking, dirty bits inflate the computed end and wrongly revert with
    /// `ReadError`.
    function testReadSliceDirtyBitsIgnored() external {
        bytes memory data = hex"00112233445566778899aabbccddeeff";
        address dataContract = deploy(data);

        bytes memory expected = LibDataContract.readSlice(dataContract, 3, 5);
        assertEq(expected, hex"3344556677");

        // Dirty start only.
        assertEq(this.readSliceDirty(dataContract, (1 << 16) | 3, 5), expected);
        // Dirty length only.
        assertEq(this.readSliceDirty(dataContract, 3, (0xdead << 16) | 5), expected);
        // Both dirty, all high bits set.
        assertEq(this.readSliceDirty(dataContract, (type(uint256).max << 16) | 3, (type(uint256).max << 16) | 5), expected);
    }

    /// Fuzz: for any in-bounds slice and any dirty high bits, the dirty call
    /// returns exactly the clean slice.
    function testReadSliceDirtyBitsFuzz(
        bytes memory data,
        uint256 startSeed,
        uint256 lengthSeed,
        uint256 dirtyStartBits,
        uint256 dirtyLengthBits
    ) external {
        uint16 start = uint16(bound(startSeed, 0, data.length));
        uint16 length = uint16(bound(lengthSeed, 0, data.length - start));
        address dataContract = deploy(data);

        bytes memory expected = LibDataContract.readSlice(dataContract, start, length);
        bytes memory actual = this.readSliceDirty(
            dataContract, uint256(start) | (dirtyStartBits << 16), uint256(length) | (dirtyLengthBits << 16)
        );
        assertEq(actual, expected);
    }

    /// The masks are exactly 16 bits wide: clean values that need more than
    /// 8 bits pass through unchanged. A slice with `start` and `length` both
    /// above 0xff round-trips byte for byte, so any mask narrower than uint16
    /// fails here.
    function testReadSliceMaskFullUint16Width() external {
        uint256 dataLength = 600;
        bytes memory data = new bytes(dataLength);
        // Non-zero, position-dependent pattern so any offset shift is
        // observable.
        for (uint256 i = 0; i < dataLength; i++) {
            data[i] = bytes1(uint8((i % 255) + 1));
        }
        address dataContract = deploy(data);

        uint16 start = 300;
        uint16 length = 260;
        bytes memory expected = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            expected[i] = data[start + i];
        }

        bytes memory slice = LibDataContract.readSlice(dataContract, start, length);
        assertEq(slice, expected);
    }

    /// A `length` stack word of `type(uint256).max` (low 16 bits all set) is
    /// the dirty value that, without masking, wraps the computed end back
    /// below the code size, slips past the bounds guard, and corrupts memory
    /// by using the raw word as the stored length and allocation size. Masked,
    /// it is a 0xffff-byte slice far past the end of this small contract and
    /// MUST revert with `ReadError`.
    function testReadSliceDirtyLengthWrapReverts() external {
        bytes memory data = hex"00112233445566778899aabbccddeeff";
        address dataContract = deploy(data);

        vm.expectRevert(ReadError.selector);
        this.readSliceDirty(dataContract, 0, type(uint256).max);
    }
}
