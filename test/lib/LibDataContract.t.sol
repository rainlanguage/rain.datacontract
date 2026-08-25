// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibMemCpy} from "rain-solmem-0.1.26/src/lib/LibMemCpy.sol";
import {LibBytes} from "rain-solmem-0.1.26/src/lib/LibBytes.sol";
import {LibPointer, Pointer} from "rain-solmem-0.1.26/src/lib/LibPointer.sol";

import {
    LibDataContract,
    DataTooLarge,
    ReadError,
    BASE_PREFIX,
    PREFIX_BYTES_LENGTH
} from "../../src/lib/LibDataContract.sol";
import {Deployer} from "./Deployer.sol";

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
        length = bound(length, uint256(type(uint16).max), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(DataTooLarge.selector, length));
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

        address dataContract = deploy(data);
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

        address dataContract = deploy(data);

        vm.expectRevert(ReadError.selector);
        (bytes memory slice) = this.readSliceExternal(dataContract, start, length);
        (slice);
    }

    /// Reading a slice over the whole contract gives the same result as reading
    /// the whole contract.
    function testSameReads(bytes memory data) public {
        address dataContract = deploy(data);

        bytes memory read = LibDataContract.read(dataContract);
        bytes memory readSlice = LibDataContract.readSlice(dataContract, 0, uint16(data.length));

        assertEq(read, readSlice);
    }

    /// Check there is always a 0 byte prefix on the underlying data contract.
    function testZeroPrefix(bytes memory data) public {
        address dataContract = deploy(data);

        uint256 firstByte;
        assembly ("memory-safe") {
            mstore(0, 0)
            // copy to scratch.
            extcodecopy(dataContract, 0, 0, 1)
            firstByte := mload(0)
        }
        assertEq(firstByte, 0);
    }

    /// Deploy a data contract from `data` and return its address, asserting
    /// the `create` succeeded so a failed deployment surfaces here rather than
    /// as a vacuous pass in the calling test.
    function deploy(bytes memory data) internal returns (address dataContract) {
        bytes memory creationCode = LibDataContract.contractCreationCode(data);
        assembly ("memory-safe") {
            dataContract := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        // Deployment of valid creation code must succeed.
        assertTrue(dataContract != address(0));
    }

    /// Writing empty data MUST produce a valid (non-empty due to the 0x00
    /// prefix) data contract whose `read` returns empty bytes WITHOUT reverting.
    /// This pins the lower boundary of the `read` size guard: a deployed empty
    /// container has `extcodesize == 1` (just the prefix byte), which is a valid
    /// read returning zero bytes, and is distinct from a non-contract address
    /// (`extcodesize == 0`) which MUST revert. Mutating the guard to e.g.
    /// `size == 1` would wrongly revert here.
    function testReadEmptyData() external {
        address dataContract = deploy("");

        // The container itself is one byte: the 0x00 prefix.
        assertEq(dataContract.code.length, 1);

        bytes memory round = LibDataContract.read(dataContract);
        assertEq(round.length, 0);
        assertEq(round, "");

        // A full-width zero-length slice over the empty contract is also valid
        // and returns empty bytes.
        bytes memory slice = LibDataContract.readSlice(dataContract, 0, 0);
        assertEq(slice.length, 0);
        assertEq(slice, "");
    }

    /// Reading a non-contract address (`extcodesize == 0`) MUST revert, even
    /// though writing empty data (above) is valid. This pins the size guard to
    /// exactly zero rather than any positive value.
    function testReadZeroCodeReverts() external {
        // Precompute an address with no code.
        address noCode = address(uint160(uint256(keccak256("definitely-not-a-data-contract"))));
        assertEq(noCode.code.length, 0);

        vm.expectRevert(ReadError.selector);
        this.readExternal(noCode);
    }

    /// The largest data that fits is `type(uint16).max - 1` bytes (the GTE guard
    /// reserves one slot for the prepended 0x00 byte so the embedded uint16
    /// length `data.length + 1` does not overflow). Round-tripping at exactly
    /// this boundary exercises the full 2-byte length field of the prefix
    /// (`shl(232, data.length + 1)`) and the prefix copy offset, which fuzzing
    /// over arbitrary `bytes` effectively never reaches.
    function testRoundLargestData() external {
        uint256 maxLength = uint256(type(uint16).max) - 1;
        bytes memory data = new bytes(maxLength);
        // Fill with a non-zero, position-dependent pattern so any byte shift or
        // truncation is observable.
        for (uint256 i = 0; i < maxLength; i++) {
            data[i] = bytes1(uint8((i % 255) + 1));
        }

        address dataContract = deploy(data);
        // Container is the data plus the single 0x00 prefix byte.
        assertEq(dataContract.code.length, maxLength + 1);

        bytes memory round = LibDataContract.read(dataContract);
        assertEq(round.length, maxLength);
        assertEq(round, data);

        // Read the final byte via a slice to pin the high end of the offset/
        // length math at the maximum size.
        bytes memory lastByte = LibDataContract.readSlice(dataContract, uint16(maxLength - 1), 1);
        assertEq(lastByte.length, 1);
        assertEq(lastByte[0], data[maxLength - 1]);
    }

    /// The largest data deployable on an EIP-170 chain is 24575 bytes: the
    /// container's runtime code is the data plus the single 0x00 prefix byte,
    /// landing exactly on EIP-170's 24576-byte cap. The library's own guard is
    /// only the uint16 encoding limit (65534 bytes) because deployment — and
    /// therefore the target chain's code size limit — is left to the caller.
    /// This test pins the boundary arithmetic (data + prefix == 24576) and the
    /// round-trip at that size; it cannot pin rejection above the cap because
    /// the test EVM does not enforce EIP-170 (`testRoundLargestData` deploys a
    /// 65535-byte runtime contract). A guard mistakenly tightened below 24575
    /// data bytes would revert here.
    function testRoundEip170BoundaryData() external {
        // EIP-170 MAX_CODE_SIZE.
        uint256 eip170CodeSizeLimit = 24576;
        uint256 dataLength = eip170CodeSizeLimit - 1;

        bytes memory data = new bytes(dataLength);
        // Fill with a non-zero, position-dependent pattern so any byte shift or
        // truncation is observable.
        for (uint256 i = 0; i < dataLength; i++) {
            data[i] = bytes1(uint8((i % 255) + 1));
        }

        address dataContract = deploy(data);
        // Runtime code is the data plus the 0x00 prefix: exactly EIP-170's cap.
        assertEq(dataContract.code.length, eip170CodeSizeLimit);

        bytes memory round = LibDataContract.read(dataContract);
        assertEq(round.length, dataLength);
        assertEq(round, data);

        // Read the final byte via a slice to pin the offset/length math at the
        // EIP-170 boundary as well.
        bytes memory lastByte = LibDataContract.readSlice(dataContract, uint16(dataLength - 1), 1);
        assertEq(lastByte.length, 1);
        assertEq(lastByte[0], data[dataLength - 1]);
    }

    /// `contractCreationCode` MUST accept the largest valid length
    /// (`type(uint16).max - 1`) and reject `type(uint16).max`. This pins the
    /// GTE (`>=`) boundary of the `DataTooLarge` guard from the accepted side;
    /// the existing revert test only covers the rejected side.
    function testContractCreationCodeLargestAccepted() external pure {
        // Largest accepted length does not revert.
        bytes memory ok = new bytes(uint256(type(uint16).max) - 1);
        LibDataContract.contractCreationCode(ok);
    }

    function testContractCreationCodeSmallestRejected() external {
        // Smallest rejected length reverts.
        uint256 tooLarge = uint256(type(uint16).max);
        vm.expectRevert(abi.encodeWithSelector(DataTooLarge.selector, tooLarge));
        this.contractCreationCodeVeryLargeData(tooLarge);
    }

    /// Re-derive the full creation code byte-for-byte from the documented
    /// opcode sequence (src/lib/LibDataContract.sol), pinning `BASE_PREFIX`
    /// and `PREFIX_BYTES_LENGTH` against their derivation instead of trusting
    /// the hardcoded constants: PUSH2 <runtime size> DUP1, PUSH1 12, PUSH1 0,
    /// CODECOPY, PUSH1 0, RETURN, then the 0x00 prefix byte and the data. Any
    /// drift between the constants and the opcode table fails here at the
    /// constants themselves rather than as an opaque round-trip mismatch.
    function testContractCreationCodeExactBytes(bytes memory data) external pure {
        vm.assume(data.length < uint256(type(uint16).max));
        bytes memory expected = abi.encodePacked(
            hex"61",
            uint16(data.length + 1), // PUSH2 runtime size incl. 0x00 prefix
            hex"80", // DUP1
            hex"600c", // PUSH1 12: runtime code offset within creation code
            hex"6000", // PUSH1 0
            hex"39", // CODECOPY
            hex"6000", // PUSH1 0
            hex"f3", // RETURN
            hex"00", // prepended zero byte: first byte of runtime code
            data
        );
        bytes memory creationCode = LibDataContract.contractCreationCode(data);
        assertEq(creationCode.length, PREFIX_BYTES_LENGTH + data.length);
        assertEq(creationCode, expected);
    }

    /// As `testContractCreationCodeExactBytes` but deterministically at the
    /// largest accepted length, where the embedded PUSH2 operand saturates at
    /// 0xffff. This pins that the `shl(232, ...)` length field lands exactly
    /// on the two PUSH2 placeholder bytes of `BASE_PREFIX`: with every length
    /// bit set, any misalignment or overlap with neighbouring opcode bytes
    /// changes the prefix and fails the comparison. Fuzzing effectively never
    /// reaches this boundary.
    function testContractCreationCodeExactBytesLargest() external pure {
        bytes memory data = new bytes(uint256(type(uint16).max) - 1);
        bytes memory creationCode = LibDataContract.contractCreationCode(data);
        assertEq(creationCode.length, PREFIX_BYTES_LENGTH + data.length);
        bytes memory expected = abi.encodePacked(hex"61ffff80600c6000396000f300", data);
        assertEq(creationCode, expected);
    }

    /// Relational pins between the two constants and within `BASE_PREFIX`
    /// itself, straight from the documented opcode table:
    /// - the PUSH1 operand for the CODECOPY source offset (byte 5 of the
    ///   prefix) is the runtime code's offset within the creation code, i.e.
    ///   `PREFIX_BYTES_LENGTH - 1` because the trailing 0x00 prefix byte is
    ///   already runtime code;
    /// - the two PUSH2 placeholder bytes (bytes 1-2) are zero so the
    ///   `or(BASE_PREFIX, shl(232, length))` in `contractCreationCode` writes
    ///   the length without clobbering opcode bits;
    /// - every bit below the 13 documented prefix bytes is zero: the table is
    ///   the whole constant, and the full-word `mstore` of the prefix leaves
    ///   only zeros in the padding region past short data.
    function testBasePrefixRelationalPins() external pure {
        bytes32 prefix = bytes32(BASE_PREFIX);
        // CODECOPY source offset operand == PREFIX_BYTES_LENGTH - 1.
        assertEq(uint8(prefix[5]), PREFIX_BYTES_LENGTH - 1);
        // PUSH2 placeholder bytes are zero.
        assertEq(uint8(prefix[1]), 0);
        assertEq(uint8(prefix[2]), 0);
        // No bits set beyond the PREFIX_BYTES_LENGTH prefix bytes.
        assertEq(BASE_PREFIX & (type(uint256).max >> (8 * PREFIX_BYTES_LENGTH)), 0);
    }

    /// `DataTooLarge` has ABI signature `DataTooLarge(uint256)`, so its
    /// selector is `bytes4(keccak256("DataTooLarge(uint256)"))` = 0x247b458c.
    /// Pinning the raw bytes means any change to the error's name or
    /// parameter types shows up as an ABI break rather than passing silently
    /// (the `abi.encodeWithSelector` revert tests recompute the selector from
    /// the declaration, so they cannot catch signature drift).
    function testDataTooLargeSelectorPinned() external pure {
        assertEq(DataTooLarge.selector, bytes4(0x247b458c));
    }

    /// `ReadError` has ABI signature `ReadError()`, so its selector is
    /// `bytes4(keccak256("ReadError()"))` = 0x26a9f61e. Pinning the raw bytes
    /// means any change to the error's name shows up as an ABI break rather
    /// than passing silently (the `vm.expectRevert(ReadError.selector)` tests
    /// recompute the selector from the declaration, so they cannot catch
    /// signature drift).
    function testReadErrorSelectorPinned() external pure {
        assertEq(ReadError.selector, bytes4(0x26a9f61e));
    }

    /// Reading a slice that ends exactly at the end of the data is valid and
    /// returns the tail bytes; reading one byte further MUST revert. This pins
    /// the `size < end` bounds check at its exact boundary deterministically
    /// (rather than relying on a fuzzed slice happening to land on the end).
    function testReadSliceExactEndBoundary() external {
        bytes memory data = hex"00112233445566778899aabbccddeeff";
        address dataContract = deploy(data);
        uint16 len = uint16(data.length);

        // Slice covering the whole contract ending exactly at the end: valid.
        bytes memory whole = LibDataContract.readSlice(dataContract, 0, len);
        assertEq(whole, data);

        // Slice of the final single byte ending exactly at the end: valid.
        bytes memory tail = LibDataContract.readSlice(dataContract, len - 1, 1);
        assertEq(tail.length, 1);
        assertEq(tail[0], data[len - 1]);

        // Zero-length slice starting exactly at the end of the data ends
        // exactly at the end, so it is valid and returns empty bytes.
        bytes memory empty = LibDataContract.readSlice(dataContract, len, 0);
        assertEq(empty.length, 0);
        assertEq(empty, "");

        // One byte past the end MUST revert.
        vm.expectRevert(ReadError.selector);
        this.readSliceExternal(dataContract, len - 1, 2);
    }

    /// A zero-length slice reads nothing, but its `start` must still be within
    /// `[0, data.length]`: the guard is `start + length <= data.length` even
    /// when `length` is zero. Starting inside the data or exactly at its end
    /// returns empty bytes; starting one byte past the end reverts, as does
    /// any farther start. This pins the `size < end` guard as a bound on
    /// `start` itself rather than only on bytes actually read.
    function testReadSliceZeroLengthPastEndReverts() external {
        bytes memory data = hex"00112233445566778899aabbccddeeff";
        address dataContract = deploy(data);
        uint16 len = uint16(data.length);

        // Zero-length slice starting inside the data: valid, empty.
        bytes memory interior = LibDataContract.readSlice(dataContract, 5, 0);
        assertEq(interior.length, 0);
        assertEq(interior, "");

        // Zero-length slice starting exactly at the end: valid, empty.
        bytes memory atEnd = LibDataContract.readSlice(dataContract, len, 0);
        assertEq(atEnd.length, 0);
        assertEq(atEnd, "");

        // Zero-length slice starting one byte past the end: reverts.
        vm.expectRevert(ReadError.selector);
        this.readSliceExternal(dataContract, len + 1, 0);

        // Any farther start also reverts, out to the uint16 maximum.
        vm.expectRevert(ReadError.selector);
        this.readSliceExternal(dataContract, type(uint16).max, 0);
    }

    /// Slice bounds are computed in uint256, so `start`/`length` combinations
    /// whose (prefix-adjusted) end exceeds `type(uint16).max` MUST still be
    /// caught by the bounds guard. If the end were truncated to 16 bits,
    /// start 65535 with length 10 would give end 10, which fits inside this
    /// small contract and would silently return zero-padded garbage from far
    /// past the end of the code instead of reverting.
    function testReadSliceEndNoUint16Wrap() external {
        bytes memory data = hex"00112233445566778899aabbccddeeff";
        address dataContract = deploy(data);

        vm.expectRevert(ReadError.selector);
        this.readSliceExternal(dataContract, type(uint16).max, 10);

        // Maximum start and length together must also revert.
        vm.expectRevert(ReadError.selector);
        this.readSliceExternal(dataContract, type(uint16).max, type(uint16).max);
    }

    /// `readSlice` registers its output with the free memory pointer: the
    /// bump covers the length word plus the data padded up to a whole 32-byte
    /// word, keeping the pointer word-aligned so later allocations neither
    /// start misaligned nor overlap the slice's final partial word. A 5 byte
    /// slice therefore consumes exactly two words: one for the length and one
    /// for the padded data.
    function testReadSliceAllocationAlignedAndPadded() external {
        bytes memory data = hex"00112233445566778899aabbccddeeff";
        address dataContract = deploy(data);

        bytes memory slice = LibDataContract.readSlice(dataContract, 3, 5);
        uint256 slicePointer;
        uint256 allocated;
        // Capture the free memory pointer before any further allocations.
        assembly ("memory-safe") {
            slicePointer := slice
            allocated := mload(0x40)
        }

        assertEq(slice, hex"3344556677");
        // Free memory pointer stays 32-byte aligned after the allocation.
        assertEq(allocated % 0x20, 0);
        // Exactly one word for the length plus one word of padded data.
        assertEq(allocated, slicePointer + 0x40);
    }

    /// `read` MUST skip the injected 0x00 prefix byte and return only the data,
    /// even when the first data byte is itself non-zero. This pins the read
    /// offset (`extcodecopy ... 1 ...`) to skip exactly one byte: a known
    /// non-zero leading data byte must appear at index 0 of the result.
    function testReadSkipsPrefixExactly() external {
        bytes memory data = hex"aabbccdd";
        address dataContract = deploy(data);

        bytes memory round = LibDataContract.read(dataContract);
        assertEq(round, data);
        // First returned byte is the first data byte, not the 0x00 prefix.
        assertEq(round[0], bytes1(0xaa));

        // Same via readSlice from offset 0.
        bytes memory slice = LibDataContract.readSlice(dataContract, 0, uint16(data.length));
        assertEq(slice, data);
        assertEq(slice[0], bytes1(0xaa));
    }

    /// `contractCreationCode` MUST allocate its output exactly as Solidity
    /// allocates `bytes`: the returned pointer is the free memory pointer at
    /// the time of the call, and afterwards the free memory pointer sits one
    /// 32-byte length word plus the word-padded content (13 prefix bytes +
    /// data) further on. Any other accounting either breaks word alignment for
    /// subsequent allocations or lets a later allocation overlap the creation
    /// code.
    function testContractCreationCodeMemoryAccounting() external pure {
        // Lengths chosen so prefix + data is: below one word (13, 17 bytes),
        // exactly one word (13 + 19 = 32, padding is a no-op), and a
        // non-aligned multi-word size (64 < 13 + 60 = 73 < 96).
        uint256[4] memory lengths = [uint256(0), 4, 19, 60];
        for (uint256 i = 0; i < lengths.length; i++) {
            bytes memory data = new bytes(lengths[i]);
            uint256 freeMemoryPointerBefore;
            assembly ("memory-safe") {
                freeMemoryPointerBefore := mload(0x40)
            }
            bytes memory creationCode = LibDataContract.contractCreationCode(data);
            uint256 freeMemoryPointerAfter;
            uint256 creationCodePointer;
            assembly ("memory-safe") {
                freeMemoryPointerAfter := mload(0x40)
                creationCodePointer := creationCode
            }
            uint256 contentLength = 13 + lengths[i];
            // Allocation starts at the old free memory pointer.
            assertEq(creationCodePointer, freeMemoryPointerBefore);
            // Output is the 13-byte prefix plus the data.
            assertEq(creationCode.length, contentLength);
            // Free memory pointer advances by the length word plus the
            // content rounded up to whole words.
            assertEq(freeMemoryPointerAfter, freeMemoryPointerBefore + 0x20 + ((contentLength + 31) / 32) * 32);
        }
    }

    /// Memory allocated AFTER `contractCreationCode` returns MUST NOT overlap
    /// the creation code: the creation code survives a subsequent dirtying
    /// allocation byte-for-byte and still deploys a contract that round-trips
    /// the data.
    function testContractCreationCodeSurvivesLaterAllocation() external {
        bytes memory data = hex"00112233445566778899aabbccddeeff";
        bytes memory creationCode = LibDataContract.contractCreationCode(data);
        bytes32 creationCodeHash = keccak256(creationCode);

        // Allocate and dirty fresh memory; a correct allocator has placed
        // this strictly after the creation code.
        bytes memory noise = new bytes(96);
        for (uint256 i = 0; i < noise.length; i++) {
            noise[i] = 0xff;
        }

        assertEq(keccak256(creationCode), creationCodeHash);

        address dataContract;
        assembly ("memory-safe") {
            dataContract := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        assertTrue(dataContract != address(0));
        assertEq(LibDataContract.read(dataContract), data);
    }

    /// `read` allocates its output at the free memory pointer and MUST bump
    /// the pointer past the allocation, rounded up to a 32-byte boundary as
    /// Solidity's allocator requires: length word plus data, padded. An
    /// unaligned or short bump would let the next allocation overlap the tail
    /// of the returned bytes. Exact expected pointers per the convention:
    /// empty data allocates just the length word (0x20); a 3-byte payload pads
    /// its data region up to a full word (0x20 + 0x20); a 32-byte payload
    /// needs no padding (0x20 + 0x20).
    function testReadAllocationRegisteredAligned() external {
        // Empty data: allocation is the zero length word only.
        checkReadAllocation("", 0x20);
        // Non-multiple-of-32 data: data region pads up to one full word.
        checkReadAllocation(hex"aabbcc", 0x20 + 0x20);
        // Exact-multiple data: no extra padding beyond the data itself.
        checkReadAllocation(new bytes(32), 0x20 + 0x20);
    }

    function checkReadAllocation(bytes memory data, uint256 expectedAllocation) internal {
        address dataContract = deploy(data);

        uint256 freeMemoryPointerBefore;
        assembly ("memory-safe") {
            freeMemoryPointerBefore := mload(0x40)
        }
        bytes memory round = LibDataContract.read(dataContract);
        uint256 freeMemoryPointerAfter;
        uint256 roundPointer;
        assembly ("memory-safe") {
            freeMemoryPointerAfter := mload(0x40)
            roundPointer := round
        }

        // The output is allocated exactly at the prior free memory pointer.
        assertEq(roundPointer, freeMemoryPointerBefore);
        // The free memory pointer moves past the aligned allocation.
        assertEq(freeMemoryPointerAfter, roundPointer + expectedAllocation);
        assertEq(round, data);
    }

    /// Deployment is left to the caller: any mechanism that works for
    /// `type(Foo).creationCode` — direct `create`, Zoltu deterministic proxy
    /// (`create2`), etc. Pin that the creation code is context independent by
    /// deploying identical bytes via `create` and `create2` and checking both
    /// round-trip the data and carry byte-identical runtime code.
    function testRoundCreationCodeCreate2(bytes memory data, bytes32 salt) external {
        vm.assume(data.length < uint256(type(uint16).max));
        address viaCreate = deploy(data);
        bytes memory creationCode = LibDataContract.contractCreationCode(data);
        address viaCreate2;
        assembly ("memory-safe") {
            viaCreate2 := create2(0, add(creationCode, 0x20), mload(creationCode), salt)
        }
        assertTrue(viaCreate2 != address(0));
        assertEq(LibDataContract.read(viaCreate2), data);
        assertEq(viaCreate2.code, viaCreate.code);
    }

    /// The `create2` salt selects the deployment address but MUST NOT leak
    /// into the deployed container: the same data deployed under two different
    /// salts lands at two different addresses carrying byte-identical runtime
    /// code that round-trips the data.
    function testRoundCreationCodeSaltIndependence(bytes memory data, bytes32 saltA, bytes32 saltB) external {
        vm.assume(data.length < uint256(type(uint16).max));
        vm.assume(saltA != saltB);
        bytes memory creationCode = LibDataContract.contractCreationCode(data);
        address viaSaltA;
        address viaSaltB;
        assembly ("memory-safe") {
            viaSaltA := create2(0, add(creationCode, 0x20), mload(creationCode), saltA)
            viaSaltB := create2(0, add(creationCode, 0x20), mload(creationCode), saltB)
        }
        assertTrue(viaSaltA != address(0));
        assertTrue(viaSaltB != address(0));
        assertTrue(viaSaltA != viaSaltB);
        assertEq(viaSaltA.code, viaSaltB.code);
        assertEq(LibDataContract.read(viaSaltA), data);
        assertEq(LibDataContract.read(viaSaltB), data);
    }

    /// The deployer's address and call path MUST NOT leak into the deployed
    /// container, and the same data deployed repeatedly MUST yield
    /// byte-identical containers: the same creation code deployed from the
    /// test contract (twice, via `create`), from two distinct `Deployer`
    /// contracts via `create`, and from one of them via `create2`, lands at
    /// distinct addresses all carrying runtime code that is exactly the single
    /// 0x00 prefix byte followed by the data, and each round-trips the data.
    function testRoundCreationCodeDeployerIndependence(bytes memory data, bytes32 salt) external {
        vm.assume(data.length < uint256(type(uint16).max));
        bytes memory creationCode = LibDataContract.contractCreationCode(data);

        Deployer deployerA = new Deployer();
        Deployer deployerB = new Deployer();

        address direct = deploy(data);
        address directAgain = deploy(data);
        address viaDeployerA = deployerA.deployCreate(creationCode);
        address viaDeployerB = deployerB.deployCreate(creationCode);
        address viaDeployerBCreate2 = deployerB.deployCreate2(creationCode, salt);

        assertTrue(viaDeployerA != address(0));
        assertTrue(viaDeployerB != address(0));
        assertTrue(viaDeployerBCreate2 != address(0));
        // Same deployer, same data, deployed twice: different address, same
        // container bytes.
        assertTrue(direct != directAgain);

        bytes memory expectedCode = abi.encodePacked(bytes1(0x00), data);
        assertEq(direct.code, expectedCode);
        assertEq(directAgain.code, expectedCode);
        assertEq(viaDeployerA.code, expectedCode);
        assertEq(viaDeployerB.code, expectedCode);
        assertEq(viaDeployerBCreate2.code, expectedCode);

        assertEq(LibDataContract.read(direct), data);
        assertEq(LibDataContract.read(viaDeployerA), data);
        assertEq(LibDataContract.read(viaDeployerB), data);
        assertEq(LibDataContract.read(viaDeployerBCreate2), data);
    }

    /// `read` never validates that the pointer is a container this library
    /// wrote: any code-bearing address is read as though it were a container,
    /// returning its code minus the first byte with no revert — even when the
    /// first byte is not the `0x00` prefix every container deployed from
    /// `contractCreationCode` output starts with (pinned by `testZeroPrefix`).
    /// Only zero-code addresses revert (`testReadZeroCodeReverts`). This pins
    /// the documented caller-precondition semantics: adding any first-byte
    /// validation to `read` fails this test.
    function testReadNonContainerShiftedCode() external {
        address notContainer = address(0xBEEF);
        vm.etch(notContainer, hex"11223344");

        bytes memory data = this.readExternal(notContainer);
        assertEq(data, hex"223344");
    }

    /// As `testReadNonContainerShiftedCode` but for `readSlice`: slices of a
    /// non-container code-bearing address come back shifted one byte (the
    /// skipped "prefix" is really its first code byte) with no revert, as long
    /// as the shifted slice stays within the code; one byte further still
    /// reverts. Adding any first-byte validation to `readSlice` fails this
    /// test.
    function testReadSliceNonContainerShiftedCode() external {
        address notContainer = address(0xBEEF);
        vm.etch(notContainer, hex"11223344");

        assertEq(this.readSliceExternal(notContainer, 0, 3), hex"223344");
        assertEq(this.readSliceExternal(notContainer, 1, 2), hex"3344");

        vm.expectRevert(ReadError.selector);
        this.readSliceExternal(notContainer, 0, 4);
    }
}
