# Dev-environment troubleshooting

The toolchain problems this repo has actually hit — and the fixes that
worked — in one place. If you're setting this repo up for the first time
and something won't build, start here.

Both of these were solved once already, but written down in two different
places: [`HANDOFF.md`](../HANDOFF.md)'s toolchain section and
[`.github/workflows/test.yml`](../.github/workflows/test.yml)'s own
comments. This page consolidates them; those two stay the originals, and
neither should drift from what's here.

## What you actually need

| Working on | Needs |
| --- | --- |
| Running the tests | Rust only — `cargo test` runs on the host target |
| Building the deployable `.wasm` | `stellar-cli`, plus the `wasm32v1-none` target |
| Deploying / invoking on testnet | `stellar-cli`, plus a funded testnet identity |

`cargo test` does **not** need `stellar-cli`, and doesn't wait on it. If all
you're doing is verifying contract logic, that's the faster path.

## Gotcha 1 — `cargo install stellar-cli` fails on Windows

**Symptom.** `cargo install stellar-cli` fails while building the CLI's own
dependency tree, complaining about a missing `dlltool.exe`.

**Why.** `stellar-cli`'s dependency tree needs MinGW binutils to link when
your Rust host toolchain is `stable-x86_64-pc-windows-gnu` (the common
default on Windows). `dlltool.exe` comes from that package, it isn't
installed by default, and adding it isn't trivial. Nothing is wrong with
your checkout or with the CLI — this is the host toolchain being the wrong
shape for a from-source build of that dependency graph.

**Fix: don't compile it — use the prebuilt release binary.**

```bash
# Find the latest release and its Windows asset
gh api repos/stellar/stellar-cli/releases/latest
# Download stellar-cli-<version>-x86_64-pc-windows-msvc.tar.gz,
# extract stellar.exe, and drop it into ~/.cargo/bin/ (already on PATH)
```

The `-msvc` build is the point: it's a **standalone executable**, so it runs
fine regardless of what your local `rustup` host toolchain is — it does not
need to match. That's why this works when `cargo install` doesn't.

**Don't retry `cargo install stellar-cli` on a Windows machine with a GNU
host toolchain** without installing MinGW binutils first; it will fail the
same way every time.

## Gotcha 2 — a fresh Linux runner can't compile `stellar-cli` either

**Symptom.** On a clean `ubuntu-latest` runner, installing the CLI from
source fails deep inside its dependency tree — typically a `pkg-config` /
missing-header error while building `libdbus-sys` or `hidapi`.

**Why.** Two system *dev* libraries that the CLI's dependency tree needs are
not present on a fresh runner image:

- **`dbus-1`** — for `libdbus-sys`, the keyring support
- **`libudev`** — for `hidapi`, the hardware-wallet (Ledger) support

`pkg-config` is needed to find them. This is the same class of problem as
Gotcha 1 (a system-level dependency of the CLI's own tree, not of this
contract), on a different OS.

**Fix.**

```bash
sudo apt-get update && sudo apt-get install -y libdbus-1-dev libudev-dev pkg-config
```

That's exactly the line the `stellar contract build` CI job runs before
`cargo install --locked stellar-cli` — see `test.yml`.

**Worth knowing: they surfaced one at a time.** `dbus-1` broke the build job
unnoticed for two runs on 2 Sept 2026 before anyone caught it; fixing it
made `libudev` appear immediately as the *next* missing dependency, with the
same failure shape and a different library name. So if that job breaks again
on a newer runner image, expect a **third** library in the same shape, not
one of these two coming back — read the actual failing crate name rather
than assuming it's the known pair.

## Other things that look like setup problems but aren't

- **`error: target 'wasm32v1-none' not found`** — add it: `rustup target add
  wasm32v1-none`. It's the current recommended Soroban target; don't "fix"
  it back to `wasm32-unknown-unknown`.
- **`Wasm does not exist` when deploying** — the build and the upload are
  two different steps. `stellar contract build` compiles locally;
  `stellar contract upload` is what puts it on testnet. Deploying a hash
  that was never uploaded fails with this. See HANDOFF.md's Deployment 4
  note.
- **A multi-party call fails with `TxBadAuthExtra`** — that's a *signing*
  problem, not a setup one, and it has its own write-up: each non-source
  auth entry has to be signed individually, not by piling up envelope
  signatures. See the `api/` repo's `test/helpers.ts` doc comment.

## If you hit a new one

Add it here, with the symptom as you saw it (the error text matters — these
are searched for). If the fix needs a change to the CI workflow, open an
issue instead: `.github/workflows/*` is maintainer-managed, and PRs are
explicitly asked not to touch it.
