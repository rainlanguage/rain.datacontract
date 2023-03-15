// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

error WriteError();

library DataContract {
    /// @return Pointer to the container that will be deployed.
    function allocate(uint256 length_) internal pure returns (bytes memory, uint256) {
        unchecked {
            // 19 = number of prefix bytes
            bytes memory container_ = new bytes(length_ + 19);
            uint256 cursor_;
            assembly ("memory-safe") {
                // 39 = number of prefix bytes + 20 bytes for length slot
                cursor_ := add(container_, 39)
            }

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
            bytes32 prefixBytes_ = hex"00000000000000000000000000_63_0000000000000000_80_60_0E_60_00_39_60_00_F3_00";
            assembly ("memory-safe") {
                let prefix_ := or(
                    prefixBytes_,
                    shr(
                        // Shift up to the spot where the length goes.
                        80, 
                        // Mask the length to 8 bytes.
                        and(
                            0xFFFFFFFFFFFFFFFF,
                            // Account for the extra 00 byte in the prefix.
                            add(length_, 1)
                        )
                    )
                )
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
}