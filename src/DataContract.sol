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
uint256 constant BASE_PREFIX = uint256(bytes32(hex"0000000000000000000000000000000000630000000080600E6000396000F300"));

uint256 constant PREFIX_BYTES_LENGTH = 15;
uint256 constant CURSOR_OFFSET = PREFIX_BYTES_LENGTH + 0x20;

library DataContract {
    function allocate(uint256 length_) internal pure returns (bytes memory, uint256) {
        unchecked {
            bytes memory container_ = new bytes(length_ + PREFIX_BYTES_LENGTH);
            uint256 cursor_;
            assembly ("memory-safe") {
                cursor_ := container_
            }
            cursor_ += CURSOR_OFFSET;

            uint256 prefix_ = BASE_PREFIX | (uint256(uint32(length_ + 1)) << 80);

            assembly ("memory-safe") {
                let location_ := sub(cursor_, 0x20)
                // We know the mload at location is zeroed out and we can do an or
                // because we allocated it as new bytes array ourselves above.
                mstore(location_, or(mload(location_), prefix_))
            }

            return (container_, cursor_);
        }
    }

    function write(bytes memory data_) internal returns (address) {
        address pointer_;
        assembly ("memory-safe") {
            pointer_ := create(0, add(data_, 0x20), mload(data_))
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
