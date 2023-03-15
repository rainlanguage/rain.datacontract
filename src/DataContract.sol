// SPDX-License-Identifier: CAL
pragma solidity ^0.8.15;

error WriteError();
error ReadError();

// SSTORE2 Verbatim reference
// https://github.com/0xsequence/sstore2/blob/master/contracts/utils/Bytecode.sol#L15
//
// 0x00    0x63         0x63XXXXXX  PUSH4 _code.length  size
// 0x01    0x80         0x80        DUP1                size size
// 0x02    0x60         0x600e      PUSH1 14            14 size size
// 0x03    0x60         0x6000      PUSH1 00            0 14 size size
// 0x04    0x39         0x39        CODECOPY            size
// 0x05    0x60         0x6000      PUSH1 00            0 size
// 0x06    0xf3         0xf3        RETURN
// <CODE>
//
// However note that 00 is also prepended (although docs say append) so there's
// an additional byte that isn't described above.
// https://github.com/0xsequence/sstore2/blob/master/contracts/SSTORE2.sol#L25
//
// Note also typo 0x63XXXXXX which indicates 3 bytes but instead 4 are used as 0x64XXXXXXXX.
//
// Note also that we don't need 4 bytes to represent the size of a contract as 24kb is the max
// PUSH2 (0x61) can be used instead of PUSH4 for code length.
// https://github.com/0xsequence/sstore2/pull/5/files
uint256 constant BASE_PREFIX = uint256(bytes32(hex"0000000000000000000000000000000000000061000080600C6000396000F300"));

uint256 constant PREFIX_BYTES_LENGTH = 13;
uint256 constant CURSOR_OFFSET = PREFIX_BYTES_LENGTH + 0x20;

library DataContract {
    function allocate(uint256 length_) internal pure returns (uint256 container_, uint256 cursor_) {
        unchecked {
            uint256 cursorOffset_ = CURSOR_OFFSET;
            uint256 prefixBytesLength_ = PREFIX_BYTES_LENGTH;
            uint256 basePrefix_ = BASE_PREFIX;
            assembly ("memory-safe") {
                // allocate output byte array - this could also be done without assembly
                // by using container_ = new bytes(size)
                container_ := mload(0x40)
                // new "memory end" including padding
                mstore(0x40, add(container_, and(add(add(length_, cursorOffset_), 0x1f), not(0x1f))))
                // store length in memory
                mstore(container_, add(length_, prefixBytesLength_))

                // cursor is where the caller will write to
                cursor_ := add(container_, cursorOffset_)

                // copy length into the 2 bytes gap in the base prefix
                let prefix_ :=
                    or(
                        basePrefix_,
                        shl(
                            // 10 bytes after the length
                            80,
                            and(
                                // mask the length to 2 bytes
                                0xFFFF,
                                add(length_, 1)
                            )
                        )
                    )

                let location_ := sub(cursor_, 0x20)
                // Because allocated memory is padded to be aligned and the
                // prefix means the length is always non-zero, it is safe to
                // simply zero out memory after the length before we OR it with
                // the prefix.
                mstore(add(container_, 0x20), 0)
                mstore(location_, or(mload(location_), prefix_))
            }
        }
    }

    function write(uint256 container_) internal returns (address) {
        address pointer_;
        assembly ("memory-safe") {
            pointer_ := create(0, add(container_, 0x20), mload(container_))
        }
        // Zero address means create failed.
        if (pointer_ == address(0)) revert WriteError();
        return pointer_;
    }

    function read(address pointer_) internal view returns (bytes memory) {
        unchecked {
            uint256 size_;
            assembly ("memory-safe") {
                size_ := extcodesize(pointer_)
            }
            // size should never be 0 because an empty write still starts
            // with the zero byte.
            if (size_ == 0) revert ReadError();
            // skip first byte.
            size_ -= 1;
            bytes memory data_ = new bytes(size_);
            assembly ("memory-safe") {
                extcodecopy(pointer_, add(data_, 0x20), 1, size_)
            }
            return data_;
        }
    }
}
