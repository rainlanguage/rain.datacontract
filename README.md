# DataContract

DataContract is a simplified reimplementation of
https://github.com/0xsequence/sstore2

- Doesn't force additonal internal allocations with ABI encoding calls
- Optimised for the case where the data to read/write and contract are 1:1
- Assembly optimisations for less gas usage
- Not shipped with other unrelated code to reduce dependency bloat
- Fuzzed with foundry
- Reverts instead of silently truncating if slices are out of range for data
- Safer start/length paradigm than start/end for slicing

It is a little more low level in that it doesn't work on `bytes` from
Solidity but instead requires the caller to copy memory directy by pointer.
https://github.com/rainprotocol/sol.lib.bytes can help with that.

## Dev stuff

### Local environment & CI

Uses nixos.

Install `nix develop` - https://nixos.org/download.html.

Run `nix develop` in this repo to drop into the shell. Please ONLY use the nix
version of `foundry` for development, to ensure versions are all compatible.

Read the `flake.nix` file to find some additional commands included for dev and
CI usage.

## Legal stuff

Everything is under DecentraLicense 1.0 (DCL-1.0) which can be found in `LICENSES/`.

This is basically `CAL-1.0` which is an open source license
https://opensource.org/license/cal-1-0

The non-legal summary of DCL-1.0 is that the source is open, as expected, but
also user data in the systems that this code runs on must also be made available
to those users as relevant, and that private keys remain private.

Roughly it's "not your keys, not your coins" aware, as close as we could get in
legalese.

This is the default situation on permissionless blockchains, so shouldn't require
any additional effort by dev-users to adhere to the license terms.

This repo is REUSE 3.2 compliant https://reuse.software/spec-3.2/ and compatible
with `reuse` tooling (also available in the nix shell here).

```
nix develop -c rainix-sol-legal
```

## Contributions

Contributions are welcome **under the same license** as above.

Contributors agree and warrant that their contributions are compliant.