# rain.datacontract

Simplified reimplementation of [sstore2](https://github.com/0xsequence/sstore2):
write arbitrary `bytes` (≤24KB) into a deployable contract and read it back.

Differences from sstore2:

- No internal ABI-encoding allocations.
- Optimised for the 1:1 data-to-contract case.
- Assembly hot path for less gas.
- No unrelated code shipped — single library.
- Fuzzed with foundry.
- Reverts on out-of-range slices instead of silently truncating.
- `start`/`length` slicing rather than `start`/`end`.

Output is creation code byte-equivalent to what Solidity would emit for
`type(Foo).creationCode`. Deployment is left to the caller — direct `create`,
Zoltu deterministic proxy, etc.

Two read functions: `read` returns the entire deployed `bytes`; `readSlice`
returns a `start`/`length` slice.

## Install

Via [soldeer](https://soldeer.xyz):

```sh
forge soldeer install rain-datacontract~<version>
```

## Develop

This repo uses [nix](https://nixos.org/download.html). The default shell is the
slim `sol-shell` from [rainix](https://github.com/rainlanguage/rainix).

```sh
nix develop          # enter the shell
forge soldeer install # install deps declared in foundry.toml
forge test
```

Tasks:

- `rainix-sol-test` — `forge test`
- `rainix-sol-static` — slither
- `rainix-sol-legal` — `reuse lint`

Use the nix-pinned `forge` for all development.

## Publish

Tag `v<x.y.z>` on `main`. The
[`Publish to Soldeer`](.github/workflows/publish-soldeer.yaml) wrapper delegates
to rainix's reusable workflow, which derives the package name from the repo name
(`rain.datacontract` → `rain-datacontract`).

## License

DecentraLicense 1.0 (DCL-1.0) — full text in
[`LICENSES/`](LICENSES/LicenseRef-DCL-1.0.txt). Roughly `CAL-1.0`
([opensource.org](https://opensource.org/license/cal-1-0)) plus user-data
disclosure obligations consistent with permissionless-blockchain assumptions.

This repo is [REUSE 3.2](https://reuse.software/spec-3.2/) compliant. Verify
locally:

```sh
nix develop -c rainix-sol-legal
```

## Contributions

Welcome under the same license. Contributors warrant that their contributions
are compliant.
