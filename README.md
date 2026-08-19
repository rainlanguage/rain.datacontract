# rain.datacontract

Simplified reimplementation of [sstore2](https://github.com/0xsequence/sstore2):
write arbitrary `bytes` (up to 65534 bytes) into a deployable contract and read
it back.

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
Zoltu deterministic proxy, etc. — and so is the target chain's code size limit:
the library only enforces its own encoding limit of 65534 data bytes, so on
EIP-170 chains (24576 runtime bytes) at most 24575 data bytes are deployable.

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

Publishing is automated: every push to `main` runs the
[`Package Release`](.github/workflows/package-release.yaml) workflow, which
delegates to rainix's `rainix-autopublish` reusable workflow with the package
name `rain-datacontract`.

The version is `foundry.toml`'s `[external.package].version` — always the NEXT,
not-yet-published version. A content gate compares what `forge soldeer push`
would upload against the newest published zip: when the content differs, the
workflow publishes that version to Soldeer, tags `sol-v<version>` with a GitHub
release, and rewrites `[external.package].version` to the next unpublished
version in a `Package Release` commit (which the workflow skips when it triggers
itself). A push whose packaged content is unchanged publishes nothing — there is
no manual tagging or version bump.

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
