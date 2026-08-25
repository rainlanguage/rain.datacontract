// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

// forge-lint: disable-next-line(unused-import)
import {LibPointer, Pointer} from "rain-solmem-0.1.26/src/lib/LibPointer.sol";
import {ReadError, DataTooLarge} from "../error/ErrDataContract.sol";

/// @dev SSTORE2 Verbatim original reference
/// https://github.com/0xsequence/sstore2/blob/master/contracts/utils/Bytecode.sol#L15
///
/// 0x00    0x63         0x63XXXXXX  PUSH4 _code.length  size
/// 0x01    0x80         0x80        DUP1                size size
/// 0x02    0x60         0x600e      PUSH1 14            14 size size
/// 0x03    0x60         0x6000      PUSH1 00            0 14 size size
/// 0x04    0x39         0x39        CODECOPY            size
/// 0x05    0x60         0x6000      PUSH1 00            0 size
/// 0x06    0xf3         0xf3        RETURN
/// <CODE>
///
/// The assembly below is a modified version of this original reference according
/// to the notes following.
///
/// However note that 00 is also prepended (although docs say append) so there's
/// an additional byte that isn't described above.
/// https://github.com/0xsequence/sstore2/blob/master/contracts/SSTORE2.sol#L25
///
/// Note also typo 0x63XXXXXX which indicates 3 bytes but instead 4 are used as
/// 0x64XXXXXXXX.
///
/// Note also that we don't need 4 bytes to represent the size of the contract
/// as `contractCreationCode` guards the embedded length (`data.length + 1`) to
/// fit in a uint16, so PUSH2 (0x61) can be used instead of PUSH4 for code
/// length.
/// This also changes the 0x600e to 0x600c as we've reduced prefix size by 2
/// relative to reference implementation.
/// https://github.com/0xsequence/sstore2/pull/5/files
///
/// The final modified bytecode is therefore:
/// 0x61         0x61XXXX    PUSH2 _code.length  size
/// 0x80         0x80        DUP1                size size
/// 0x60         0x600c      PUSH1 12            12 size size
/// 0x60         0x6000      PUSH1 00            0 12 size size
/// 0x39         0x39        CODECOPY            size
/// 0x60         0x6000      PUSH1 00            0 size
/// 0xf3         0xf3        RETURN
/// 0x00         0x00        <extra byte prepended by SSTORE2>
/// <CODE>
uint256 constant BASE_PREFIX = 0x61_0000_80_600C_6000_39_6000_F3_00_00000000000000000000000000000000000000;

/// @dev Length of the prefix that converts in memory data to a deployable
/// contract.
uint256 constant PREFIX_BYTES_LENGTH = 13;

/// @title DataContract
///
/// DataContract is a simplified reimplementation of
/// https://github.com/0xsequence/sstore2
///
/// - Doesn't force additonal internal allocations with ABI encoding calls
/// - Optimised for the case where the data to read/write and contract are 1:1
/// - Assembly optimisations for less gas usage
/// - Not shipped with other unrelated code to reduce dependency bloat
/// - Fuzzed with foundry
library LibDataContract {
    /// Given some data in memory, prepares the creation code for a contract that
    /// will contain that data when deployed. The caller is responsible for
    /// actually deploying the creation code, which should be compatible with any
    /// normal method that works for `type(Foo).creationCode` such as `create` or
    /// a deterministic deployment proxy. Usual considerations such as checking
    /// the success of contract creation after deployment all apply.
    /// @param data The data to be included in the deployed contract. This can be
    /// any data up to 65534 bytes (`type(uint16).max - 1`, as the embedded
    /// uint16 length is `data.length + 1` for the prepended zero byte). Whether
    /// the creation code can actually be deployed is subject to the target
    /// chain's code size limit, e.g. EIP-170 chains cap runtime code at 24576
    /// bytes so at most 24575 bytes of data are deployable there.
    /// @return creationCode The creation code that can be deployed to create a
    /// contract containing the data.
    function contractCreationCode(bytes memory data) internal pure returns (bytes memory creationCode) {
        // GTE here because of the extra 0 byte that needs to be accounted for.
        if (data.length >= uint256(type(uint16).max)) {
            revert DataTooLarge(data.length);
        }
        uint256 prefixBytesLength = PREFIX_BYTES_LENGTH;
        uint256 basePrefix = BASE_PREFIX;
        assembly ("memory-safe") {
            // allocate output byte array
            creationCode := mload(0x40)
            // new "memory end" including padding
            let contentLength := add(prefixBytesLength, mload(data))
            let paddedContentLength := and(add(contentLength, 0x1f), not(0x1f))
            let totalLength := add(paddedContentLength, 0x20)
            mstore(0x40, add(creationCode, totalLength))
            mstore(creationCode, contentLength)
            let prefix :=
                or(
                    basePrefix,
                    shl(
                        // Length sits 29 bytes from the right
                        232,
                        // Length fits in 2 bytes as asserted above.
                        add(mload(data), 1)
                    )
                )
            mstore(add(creationCode, 0x20), prefix)
            // copy data to end of prefix in creation code
            let dataPointer := add(data, 0x20)
            let creationCodeDataPointer := add(creationCode, add(0x20, prefixBytesLength))
            mcopy(creationCodeDataPointer, dataPointer, mload(data))
        }
    }

    /// Reads data back from a previously deployed data contract.
    /// Almost verbatim Solidity docs.
    /// https://docs.soliditylang.org/en/v0.8.17/assembly.html#example
    /// Notable difference is that we skip the first byte when we read as it is
    /// a `0x00` prefix that `contractCreationCode` bakes into the deployed
    /// code.
    ///
    /// The first byte is skipped unconditionally and never inspected, so
    /// nothing here distinguishes a data contract from any other code-bearing
    /// address. Reading an address that is not a data contract silently
    /// returns its code minus the first byte as though it were data; only an
    /// address with no code at all reverts with `ReadError`.
    /// @param pointer The address of the data contract to read from. MUST be a
    /// data contract deployed from `contractCreationCode` output (or an
    /// equivalent scheme whose leading byte can be safely ignored); this is the
    /// caller's responsibility and is never checked here.
    /// @return data The data read from the data contract. First byte is skipped
    /// and contract is read completely to the end.
    function read(address pointer) internal view returns (bytes memory data) {
        uint256 size;
        assembly ("memory-safe") {
            // Retrieve the size of the code, this needs assembly.
            size := extcodesize(pointer)
        }
        if (size == 0) revert ReadError();
        assembly ("memory-safe") {
            // Skip the first byte.
            size := sub(size, 1)
            // Allocate output byte array - this could also be done without
            // assembly by using data = new bytes(size)
            data := mload(0x40)
            // New "memory end" including padding.
            // Compiler will optimise away the double constant addition.
            mstore(0x40, add(data, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            // Store length in memory.
            mstore(data, size)
            // actually retrieve the code, this needs assembly
            // skip the first byte
            extcodecopy(pointer, add(data, 0x20), 1, size)
        }
    }

    /// Hybrid of address-only read, SSTORE2 read and Solidity docs.
    /// Unlike SSTORE2, reading past the end of the data contract WILL REVERT.
    /// The bound applies to `start` itself, not only to bytes actually read:
    /// `start + length <= data.length` must hold even when `length` is zero,
    /// so a zero-length slice is valid only for `start` in `[0, data.length]`
    /// and reverts when `start` is past the end of the data.
    ///
    /// As with `read`, the pointer is never validated: any address bearing
    /// enough code for the requested slice is sliced as though it were a
    /// data contract (offsets shifted one byte past its first code byte) without
    /// reverting.
    /// @param pointer As per `read`.
    /// @param start Starting offset for reads from the data contract.
    /// @param length Number of bytes to read.
    /// @return data `length` bytes copied from the data contract, starting at
    /// data offset `start` (code offset `start + 1`; the `0x00` prefix byte is
    /// not addressable).
    function readSlice(address pointer, uint16 start, uint16 length) internal view returns (bytes memory data) {
        uint256 size;
        // uint256 offset and end avoids overflow issues from uint16.
        uint256 offset;
        uint256 end;
        assembly ("memory-safe") {
            // Skip the first byte.
            offset := add(start, 1)
            end := add(offset, length)
            // Retrieve the size of the code, this needs assembly.
            size := extcodesize(pointer)
        }
        if (size < end) revert ReadError();
        assembly ("memory-safe") {
            // Allocate output byte array - this could also be done without
            // assembly by using data = new bytes(size)
            data := mload(0x40)
            // New "memory end" including padding.
            // Compiler will optimise away the double constant addition.
            mstore(0x40, add(data, and(add(add(length, 0x20), 0x1f), not(0x1f))))
            // Store length in memory.
            mstore(data, length)
            // actually retrieve the code, this needs assembly
            extcodecopy(pointer, add(data, 0x20), offset, length)
        }
    }
}
