# DataContract

DataContract is a simplified reimplementation of https://github.com/0xsequence/sstore2

- No internal use of abi.encodePacked to avoid rendundant memory allocations
- Optimised for the case where the entire data to read/write and contract are 1:1
- Some assembly optimisations for less gas usage
- Not shipped with other unrelated code to reduce dependency bloat
- Fuzzed with foundry