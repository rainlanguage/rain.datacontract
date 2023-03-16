# DataContract

DataContract is a simplified reimplementation of
https://github.com/0xsequence/sstore2
- Doesn't force additonal internal allocations with ABI encoding calls
- Optimised for the case where the data to read/write and contract are 1:1
- Assembly optimisations for less gas usage
- Not shipped with other unrelated code to reduce dependency bloat
- Fuzzed with foundry
It is a little more low level in that it doesn't work on `bytes` from
Solidity but instead requires the caller to copy memory directy by pointer.
https://github.com/rainprotocol/sol.lib.bytes can help with that.