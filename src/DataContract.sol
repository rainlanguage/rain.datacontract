// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

error WriteError();

uint256 constant PREFIX_BYTES_LENGTH = 19;
uint256 constant CURSOR_OFFSET = PREFIX_BYTES_LENGTH + 0x20;

library DataContract {
    /// @return Pointer to the container that will be deployed.
    function allocate(uint256 length_) internal pure returns (bytes memory, uint256) {
        unchecked {
            bytes memory container_ = new bytes(length_ + PREFIX_BYTES_LENGTH);
            uint256 cursor_;
            assembly ("memory-safe") {
                cursor_ := container_
            }
            cursor_ += CURSOR_OFFSET;

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
            bytes32 prefix_ = bytes32(hex"0000000000000000000000000063000000000000000080600E6000396000F300")
                | bytes32(uint256(uint32(length_ + 1)) << 80);

            assembly ("memory-safe") {
                mstore(sub(cursor_, 0x20), prefix_)
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
            uint256 codesize_;
            assembly ("memory-safe") { codesize_ := extcodesize(pointer_) }
            uint256 offset_ = PREFIX_BYTES_LENGTH;
            uint256 length_ = codesize_ - offset_;
            bytes memory data_ = new bytes(length_);
            assembly ("memory-safe") {
                extcodecopy(pointer_, add(data_, 0x20), offset_, length_)
            }
            return data_;
        }

    } 
}
