# Rust

## Detect

`Cargo.toml`. A `[workspace]` section with `members` means a workspace - `cargo build`
handles all of it, so do not build a matrix over the members. `[[bin]]` or `src/main.rs`
means a binary; `src/lib.rs` alone means a library.

`rust-toolchain.toml` pins the toolchain. Use it if present rather than asking.

## Healthy looks like

- `Cargo.lock` committed. Required for a binary; optional but recommended for a library,
  and its absence makes CI non-reproducible.
- Tests - unit tests inline with `#[cfg(test)]`, integration tests in `tests/`.
- `rustfmt.toml` and `clippy.toml` are optional; defaults are good and widely used.
- An MSRV declared as `rust-version` in `Cargo.toml`, if the crate claims to support one.

## Commands

| Job | Command |
|---|---|
| Build | `cargo build --release --locked` |
| Test | `cargo test --locked --all-features` |
| Lint | `cargo clippy --all-targets --all-features -- -D warnings` |
| Format check | `cargo fmt --all --check` |
| Audit | `cargo audit`, or `cargo deny check` |
| Docs | `cargo doc --no-deps` |

`--locked` on every command. It fails if `Cargo.lock` would change, which is exactly the
signal CI should give rather than silently resolving to different versions.

`-D warnings` on clippy makes lints a gate rather than a suggestion. Recommend it, but
confirm - on an existing codebase it may fail immediately, which is a finding to raise
rather than a reason to soften the flag.

## Setup and caching

```yaml
- uses: dtolnay/rust-toolchain@stable    # or @<version>, or reads rust-toolchain.toml
  with:
    components: clippy, rustfmt
- uses: Swatinem/rust-cache@v2
```

Rust builds are slow and the cache matters more than in most ecosystems. `Swatinem/rust-cache`
handles the target directory and registry properly; plain `actions/cache` on `~/.cargo`
usually is not enough.

## Artifacts

| Artifact | When | Registry |
|---|---|---|
| **Static binaries** | a CLI, a service | release assets, one per target |
| **Container image** | a service | GHCR. Multi-stage with a `scratch`/`distroless` final layer |
| **Crate** | a library | crates.io, or a private registry |

Cross-compilation needs a target toolchain (`rustup target add`) and, for anything with C
dependencies, a linker - `cross` handles it. `musl` targets give a genuinely static binary;
the default `gnu` target does not.

## Tagging

crates.io enforces semver, and **a published version can never be replaced** - only
yanked. That makes an accidental publish permanent, so a release job publishing to
crates.io deserves a manual approval gate. Say so.

The version lives in `Cargo.toml`. `cargo-release` or `release-plz` automate the bump and
tag if the user wants it; otherwise the tag and the manifest have to be kept in sync
manually, which is a decision to confirm.

## Notes

- Compile times make a full matrix expensive. Recommend one primary target on every push
  and the full matrix only on release.
- `cargo audit` needs the advisory database, which it fetches - it will fail on a runner
  with no network egress.
- CodeQL does not support Rust. `cargo clippy` plus `cargo deny` is the substitute; say so
  rather than writing a CodeQL job that will not work.
