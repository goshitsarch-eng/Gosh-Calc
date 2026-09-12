# Release Pipeline Report — v0.1.0-rc.1

Push-to-green record for the Gosh-Calc release pipeline: first full
tag-driven release, from initial pipeline commit to published,
verified pre-release. Date: 2026-09-12 (UTC).

## Pipeline under test

| Item | Value |
| ---- | ----- |
| Workflows | `.github/workflows/ci.yml` (`CI`), `.github/workflows/release.yml` (`Release`) |
| Trigger | Tag push `v0.1.0-rc.1` (matches `v[0-9]*.[0-9]*.[0-9]*`) |
| Runners | `ubuntu-24.04` (CI check, gate, x86_64 build, publish), `ubuntu-24.04-arm` (aarch64 build) |
| Version sources | Tag `v0.1.0-rc.1`, `Cargo.toml` `0.1.0`, metainfo `<release version="0.1.0">`; gate enforces tag-stem == Cargo == metainfo, derives `prerelease=true` from the `-rc.1` suffix |
| Permissions | Top-level `permissions: {}`; `contents: read` on gate/build, `contents: write` on publish only |
| Processes | gate → build matrix (x86_64 + aarch64, `fail-fast`) → publish (needs gate+build; regenerates `SHA256SUMS`, runs `verify-release.sh`, creates release via pinned `softprops/action-gh-release`) |

Pipeline commits on `main` (all pushed this session):

| Commit | Change |
| ------ | ------ |
| `3ef97a2` | CI + release pipeline, scripts, docs |
| `875cba5` | Install `elfutils` (eu-strip) on build legs |
| `b7dd32f` | `--default-branch=stable` for flatpak-builder |
| `fd1031d` | Install `librsvg2-common` (SVG loader) on build legs |
| `0307332` | Drain `grep` pipes instead of `-q` under `pipefail` |
| `7575548` | This push-to-green report (`docs/release/REPORT.md`) |

## Test tag

`v0.1.0-rc.1` (annotated) — a safe pre-release tag; no production
tags or releases existed. After each fix commit the tag was deleted
locally + remotely and recreated at the new `main` head, then pushed
to retrigger `Release`. This is allowed by `RELEASES.md` because no
release had been published for the tag (publish was skipped/failed on
every attempt before the final one); nothing published was ever
moved or overwritten.

The tag and its pre-release are **kept**, not removed: repo policy
(`RELEASES.md`) forbids deleting published releases, and the
artifacts are genuine release candidates.

## Runs

CI (all green, 6/6, one per `main` push):

- https://github.com/goshitsarch-eng/Gosh-Calc/actions/runs/34663068266 (success)
- https://github.com/goshitsarch-eng/Gosh-Calc/actions/runs/34664062722 (success)
- https://github.com/goshitsarch-eng/Gosh-Calc/actions/runs/34664823622 (success)
- https://github.com/goshitsarch-eng/Gosh-Calc/actions/runs/34665588351 (success)
- https://github.com/goshitsarch-eng/Gosh-Calc/actions/runs/34666370811 (success)
- https://github.com/goshitsarch-eng/Gosh-Calc/actions/runs/34667136038 (success, HEAD `7575548`)

Release (tag `v0.1.0-rc.1`):

| Run | Result | Root cause |
| --- | ------ | ---------- |
| https://github.com/goshitsarch-eng/Gosh-Calc/actions/runs/34663280584 | failure | flatpak-builder finish phase: `Failed to execute child process "eu-strip"` (missing `elfutils` on runners); x86_64 leg cancelled by fail-fast |
| https://github.com/goshitsarch-eng/Gosh-Calc/actions/runs/34664071127 | failure | `flatpak build-bundle`: `Refspect 'app/dev.goshapps.calc/aarch64/stable' not found` — builder exports branch `master` by default, script asked for `stable` |
| https://github.com/goshitsarch-eng/Gosh-Calc/actions/runs/34664826258 | failure | x86_64 `appstreamcli compose`: `file-read-error` + `filters-but-no-output` — no gdk-pixbuf SVG loader on the runner (`--no-install-recommends`); aarch64 passed |
| https://github.com/goshitsarch-eng/Gosh-Calc/actions/runs/34665590772 | failure | publish `verify-release.sh` falsely reported both tarballs as lacking their binary: `tar tzf … | grep -q` under `set -o pipefail` — grep exits early, tar dies of SIGPIPE, pipeline fails. Reproduced locally: pre-fix script 10/10 fail, fixed script 20/20 pass on the CI-built artifacts |
| https://github.com/goshitsarch-eng/Gosh-Calc/actions/runs/34666372976 | **success** | gate ✓, both build legs ✓, publish ✓ |

No required step was ever neutered (`|| true`, `continue-on-error`):
every failure was fixed at its root cause in the repo and rerun.

Release URL: https://github.com/goshitsarch-eng/Gosh-Calc/releases/tag/v0.1.0-rc.1
(name `gosh-calc 0.1.0-rc.1`, `isPrerelease: true`, auto-generated notes).

## Published artifacts

| Asset | Size (bytes) | SHA-256 |
| ----- | ------------ | ------- |
| `gosh-calc-0.1.0-rc.1-x86_64.tar.gz` | 12491963 | `1c647772bc10d65825f4c843ba815766dd518df3a5159efe81ff95f897203e68` |
| `gosh-calc-0.1.0-rc.1-x86_64.flatpak` | 7920920 | `85db43c516c9a215dbd07871e960d946891955cbbc9c0305050d44fa140fd341` |
| `gosh-calc-0.1.0-rc.1-aarch64.tar.gz` | 11937128 | `ebcfd2925f9b2d96e7a570d9d3c0f1c95c70aa68cd7ba8c5b2a621f64616b58d` |
| `gosh-calc-0.1.0-rc.1-aarch64.flatpak` | 7151592 | `b1f9cfb0748e5360eef751678ae85322dc7ed93c5bea73260d89840947fac970` |
| `SHA256SUMS` | 408 | (covers exactly the four files above) |

Names match `PACKAGING.md` exactly; all sizes non-zero; no duplicates.

## Verification results (all observed, local host x86_64)

- `gh release download v0.1.0-rc.1` + `sha256sum -c SHA256SUMS`: all four `OK`.
- `scripts/verify-release.sh --version 0.1.0-rc.1 --dir <download-dir>`: `PASS: 4 file(s)`.
- Tarball extraction: each yields the documented 6-entry top dir
  (`gosh-calc`, desktop, metainfo, icon, README, LICENSE).
- `file(1)` on extracted binaries:
  - x86_64: `ELF 64-bit LSB pie executable, x86-64, … stripped`
  - aarch64: `ELF 64-bit LSB pie executable, ARM aarch64, … stripped`
- Flatpak bundles installed with `flatpak install --user`:
  refs `app/dev.goshapps.calc/x86_64/stable` and
  `app/dev.goshapps.calc/aarch64/stable` deployed; `file(1)` on the
  deployed binaries confirms x86-64 and ARM aarch64 respectively.
  (Installs were uninstalled afterwards; a pre-existing
  `x86_64/master` dev install was left untouched.)
- Launch (display available): x86_64 tarball binary and x86_64
  Flatpak each stayed alive past an 8–10 s `timeout` (exit 124) with
  only benign warnings (icon-theme fallback, xdg icon protocol,
  portal property cache). The aarch64 binaries cannot execute on
  this host (no aarch64 CPU/runtime) — expected; their arch is
  verified via `file(1)`.
