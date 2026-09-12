# CI Architecture

Two workflows, split by trust: `ci.yml` verifies, `release.yml` publishes.
There are no other workflows; anything that creates a GitHub release must
go through `release.yml`.

## Job graphs

`ci.yml` — every branch push and pull request, never publishes:

```text
check (ubuntu-24.04): checkout -> toolchain -> cache -> apt
  -> cargo fmt --check -> cargo build --locked
  -> cargo clippy --all-targets -- -D warnings -> cargo test --locked
```

`push.branches: ['**']` matches branches only, so tag pushes do not run
CI (the release pipeline builds the tag itself). Permissions:
`contents: read`.

`release.yml` — tag pushes only (`v[0-9]*.[0-9]*.[0-9]*`, e.g. `v0.1.0`,
`v0.2.0-rc.1`):

```text
gate (ubuntu-24.04)
  └─ version-consistency gate: tag vs Cargo.toml vs metainfo
     outputs: version (full tag version), prerelease (bool)
        │
        ▼
build matrix (needs: [gate], fail-fast)
  ├─ x86_64  on ubuntu-24.04      (native)
  └─ aarch64 on ubuntu-24.04-arm  (native)
     each: toolchain -> cache (per-arch key) -> apt + Flatpak SDK
       -> scripts/package-release.sh -> upload-artifact dist-<arch>
        │
        ▼
publish (needs: [gate, build], runs after ALL arch legs)
  └─ download all dist-* -> regenerate SHA256SUMS
    -> scripts/verify-release.sh -> softprops/action-gh-release
```

## Atomicity

- `needs: [gate, build]` waits for every matrix leg; any failure (or
  cancellation via `fail-fast`) skips `publish`. A release either ships
  all four artifacts plus `SHA256SUMS`, or nothing is published.
- `publish` re-verifies the downloaded set with
  `scripts/verify-release.sh` (naming, sizes, tarball integrity, `file(1)`
  arch of the embedded binaries, checksum coverage, `sha256sum -c`)
  before creating the release.
- `concurrency: release-${{ github.ref }}` serializes re-runs on one tag
  without cancelling (re-pushed tags queue instead of double-publishing).

## Permissions (least privilege)

Top level is `permissions: {}` (default deny). Per job:

| Job             | Permissions      | Why                                  |
| --------------- | ---------------- | ------------------------------------ |
| `gate`          | `contents: read` | check out the tag                    |
| `build`         | `contents: read` | check out the tag                    |
| `publish`       | `contents: write`| create the release + upload assets   |

`ci.yml` uses a single top-level `contents: read`. No workflow has more
than it needs, and `publish` is the only job in the repo that can write.

## Pinned actions

Every third-party action is pinned by full commit SHA with a version
comment (no `@main` / `@vN` floaters):

| Action                      | Pin                                        | Version          |
| --------------------------- | ------------------------------------------ | ---------------- |
| `actions/checkout`          | `11bd71901bbe5b1630ceea73d27597364c9af683` | v4.2.2           |
| `dtolnay/rust-toolchain`    | `6bed0761d98439e5a578e2877258200ad565ba87` | stable 2026-09-12|
| `Swatinem/rust-cache`       | `98c8021b550208e191a6a3145459bfc9fb29c4c0` | v2.8.0           |
| `actions/upload-artifact`   | `ea165f8d65b6e75b540449e92b4886f43607fa02` | v4.6.2           |
| `actions/download-artifact` | `d3f86a106a0bac45b974a628896c90dbdf5c8093` | v4.3.0           |
| `softprops/action-gh-release`| `72f2c25fcb47643c292f7107632f7a47c1df5cd8`| v2.3.2           |

To bump a pin: resolve the new tag to its commit
(`git ls-remote https://github.com/<owner>/<repo>.git '<tag>^{}'`,
falling back to `<tag>` for lightweight tags), replace the SHA, and
update the comment plus this table. For `dtolnay/rust-toolchain`
(which tracks a `stable` branch), record the resolution date.

## Where logic lives

YAML is orchestration-only: triggers, runners, permissions, setup steps,
artifact handoff. All packaging and verification logic lives in repo
scripts so it runs identically locally and in CI:

- `scripts/package-release.sh` — build, `file(1)` arch check, tarball,
  Flatpak bundle, per-arch checksums.
- `scripts/verify-release.sh` — the publish gate, also usable locally.

The one exception is the `gate` job's version check, which is ~25 lines
of inline Python: it is CI-specific (reads `GITHUB_REF_NAME`, writes
`GITHUB_OUTPUT`) and too small to justify another script file. Its rule
is mirrored by `package-release.sh`'s own consistency check, so local
packaging enforces the same invariant.

## Caching

`Swatinem/rust-cache` caches the Cargo registry and `target/`. The
release matrix uses `shared-key: release-<arch>` so the x86_64 and
aarch64 legs never share (and poison) each other's cache. CI uses the
default key on its single runner.
