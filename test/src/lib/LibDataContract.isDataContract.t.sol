// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {LibDataContract, PREFIX_BYTES_LENGTH} from "../../../src/lib/LibDataContract.sol";

contract LibDataContractIsDataContractTest is Test {
    /// Creation code built from the documented opcode table, independent of
    /// `contractCreationCode`.
    function opcodeTableCreationCode(uint16 lengthField, bytes memory payload) internal pure returns (bytes memory) {
        return abi.encodePacked(hex"61", lengthField, hex"80600c6000396000f300", payload);
    }

    function truncate(bytes memory b, uint256 length) internal pure {
        assembly ("memory-safe") {
            mstore(b, length)
        }
    }

    function testIsDataContractRoundTrip(bytes memory data) external pure {
        vm.assume(data.length < uint256(type(uint16).max));
        assertTrue(LibDataContract.isDataContract(LibDataContract.contractCreationCode(data)));
        assertTrue(LibDataContract.isDataContract(opcodeTableCreationCode(uint16(data.length + 1), data)));
    }

    function testIsDataContractEmptyPayload() external pure {
        assertTrue(LibDataContract.isDataContract(LibDataContract.contractCreationCode("")));
        assertTrue(LibDataContract.isDataContract(opcodeTableCreationCode(1, "")));
    }

    function testIsDataContractLargestPayload() external pure {
        bytes memory data = new bytes(uint256(type(uint16).max) - 1);
        for (uint256 i = 0; i < data.length; i++) {
            data[i] = bytes1(uint8((i % 255) + 1));
        }
        assertTrue(LibDataContract.isDataContract(LibDataContract.contractCreationCode(data)));
        assertTrue(LibDataContract.isDataContract(opcodeTableCreationCode(type(uint16).max, data)));
    }

    /// Bytes in memory past the end of the code are not part of the code.
    function testIsDataContractIgnoresMemoryPastEnd(bytes32 seed, uint256 length) external pure {
        length = bound(length, 0, 0x20 - PREFIX_BYTES_LENGTH - 1);
        bytes memory data = abi.encodePacked(seed);
        truncate(data, length);
        bytes memory code = LibDataContract.contractCreationCode(data);
        uint256 codeLength = code.length;
        assembly ("memory-safe") {
            let p := add(code, 0x20)
            mstore(p, or(mload(p), shr(mul(codeLength, 8), not(0))))
        }
        assertTrue(LibDataContract.isDataContract(code));
    }

    function testIsDataContractPrefixByteChangedExhaustive() external pure {
        bytes memory code = LibDataContract.contractCreationCode(hex"aabbccddeeff");
        for (uint256 i = 0; i < PREFIX_BYTES_LENGTH; i++) {
            bytes1 original = code[i];
            for (uint8 delta = type(uint8).max; delta > 0; delta--) {
                code[i] = original ^ bytes1(delta);
                assertFalse(LibDataContract.isDataContract(code));
            }
            code[i] = original;
        }
        assertTrue(LibDataContract.isDataContract(code));
    }

    function testIsDataContractPrefixByteChanged(bytes memory data, uint256 index, uint8 delta) external pure {
        vm.assume(data.length < uint256(type(uint16).max));
        vm.assume(delta != 0);
        index = bound(index, 0, PREFIX_BYTES_LENGTH - 1);
        bytes memory code = LibDataContract.contractCreationCode(data);
        code[index] = code[index] ^ bytes1(delta);
        assertFalse(LibDataContract.isDataContract(code));
    }

    function testIsDataContractWrongLengthField(bytes memory data, uint16 lengthField) external pure {
        vm.assume(data.length < uint256(type(uint16).max));
        vm.assume(lengthField != data.length + 1);
        assertFalse(LibDataContract.isDataContract(opcodeTableCreationCode(lengthField, data)));
    }

    /// The field counts the prepended zero byte, so the bare payload length is
    /// wrong.
    function testIsDataContractLengthFieldOffByOne(bytes memory data) external pure {
        vm.assume(data.length < uint256(type(uint16).max) - 1);
        assertFalse(LibDataContract.isDataContract(opcodeTableCreationCode(uint16(data.length), data)));
        assertFalse(LibDataContract.isDataContract(opcodeTableCreationCode(uint16(data.length + 2), data)));
    }

    function testIsDataContractTrailingBytes(bytes memory data, bytes memory trailing) external pure {
        vm.assume(data.length < uint256(type(uint16).max));
        vm.assume(trailing.length > 0);
        assertFalse(LibDataContract.isDataContract(bytes.concat(LibDataContract.contractCreationCode(data), trailing)));
    }

    function testIsDataContractTruncatedPayload(bytes memory data, uint256 cut) external pure {
        vm.assume(data.length > 0 && data.length < uint256(type(uint16).max));
        cut = bound(cut, 1, data.length);
        bytes memory code = LibDataContract.contractCreationCode(data);
        truncate(code, code.length - cut);
        assertFalse(LibDataContract.isDataContract(code));
    }

    function testIsDataContractShorterThanPrefix(bytes memory data, uint256 length) external pure {
        vm.assume(data.length < uint256(type(uint16).max));
        length = bound(length, 0, PREFIX_BYTES_LENGTH - 1);
        bytes memory code = LibDataContract.contractCreationCode(data);
        truncate(code, length);
        assertFalse(LibDataContract.isDataContract(code));
    }

    /// The prefix an unguarded encoder writes: the size field wraps to
    /// `(payload length + 1) mod 2^16`.
    function testIsDataContractPayloadTooLargeForSizeField(uint16 wrapped) external pure {
        uint256 payloadLength = uint256(type(uint16).max) + wrapped;
        assertFalse(LibDataContract.isDataContract(opcodeTableCreationCode(wrapped, new bytes(payloadLength))));
    }

    function testIsDataContractSmallestPayloadTooLarge() external pure {
        assertFalse(LibDataContract.isDataContract(opcodeTableCreationCode(0, new bytes(uint256(type(uint16).max)))));
        assertFalse(
            LibDataContract.isDataContract(
                opcodeTableCreationCode(type(uint16).max, new bytes(uint256(type(uint16).max)))
            )
        );
    }
}
