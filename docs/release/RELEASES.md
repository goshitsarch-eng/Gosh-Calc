# Releases

How versions, tags, and published releases fit together. For the
step-by-step runbook, see [docs/RELEASING.md](../RELEASING.md).

## Version sources

Three places carry the version; the release gate requires them to agree:

| Source                                        | Example                 |
| --------------------------------------------- | ----------------------- |
| `Cargo.toml` `package.version`                | `0.1.0`                 |
| `resources/dev.goshapps.calc.metainfo.xml`    | `<release version="0.1.0" ...>` |
| Git tag                                       | `v0.1.0`                |

Rule (enforced by the `gate` job and mirrored by
`scripts/package-release.sh`):

- The tag minus its `v` prefix must equal `Cargo.toml` exactly, or its
  `-suffix`-stripped stem must (so `v0.2.0-rc.1` is allowed while
  `Cargo.toml` says `0.2.0`).
- The metainfo release version must equal `Cargo.toml` exactly.
- Artifact file names use the full tag version (`-rc.1` included).

Bump all three together in one commit (plus `Cargo.lock` and a
regenerated `flatpak/cargo-sources.json` if dependencies changed).

## Pre-releases

Any tag with a `-suffix` (`v0.2.0-rc.1`, `v0.2.0-beta`) is published as
a GitHub pre-release (`prerelease: true`, derived from the tag name).
There is no separate track: the same gate, matrix, and verification
apply. `generate_release_notes: true` fills in the notes automatically.

## Tag -> release flow

1. Maintainer pushes a tag matching `v[0-9]*.[0-9]*.[0-9]*`.
2. `gate` checks version consistency and exports `version`/`prerelease`.
3. The `build` matrix packages natively on x86_64 and aarch64 runners
   (tarball + Flatpak bundle + per-arch checksums each) and uploads
   `dist-<arch>` artifacts.
4. `publish` downloads both sets, regenerates the single `SHA256SUMS`,
   runs `scripts/verify-release.sh` over the full set, then creates
   the GitHub release with the four artifacts plus `SHA256SUMS`.

Any failure in steps 2–4 stops the pipeline before anything is
published; fix forward and re-run (re-tag only if the tag itself was
wrong — see below).

## Verifying a release

Download the artifacts you want plus `SHA256SUMS` into one directory:

```sh
sha256sum -c SHA256SUMS
```

For a full gate-equivalent check (naming, sizes, tarball integrity,
embedded-binary arch, exact checksum coverage), point the repo script
at the directory:

```sh
scripts/verify-release.sh --version 0.1.0 --dir <download-dir>
```

## Re-tags and retries

- **Build/publish failed, tag content is right:** re-run the failed
  workflow from the GitHub UI (or push an empty commit to nothing —
  prefer re-run; the tag still points at the same commit).
- **Tag points at the wrong commit or version:** delete the tag
  locally and remotely, fix, re-tag. Never force-move a tag that
  already has a published release; cut a new version instead.
- **Published release is broken:** publish a fixed version. Editing or
  deleting published assets breaks checksums users may have recorded.

## Troubleshooting

| Symptom                                        | Likely cause and fix                                  |
| ---------------------------------------------- | ----------------------------------------------------- |
| `gate` fails: tag vs Cargo mismatch            | Tag typo, or version bump commit missing; re-tag.     |
| `gate` fails: metainfo vs Cargo                | Forgot the metainfo `<release>` entry; bump it.       |
| Build fails in `cargo build --release`         | Real compile error on that arch; reproduce via `scripts/package-release.sh --arch ...` if you have the hardware, else inspect the log. |
| Build fails in `flatpak-builder`               | Stale `flatpak/cargo-sources.json` (regenerate per CONTRIBUTING.md) or missing SDK on the runner (check the SDK install step). |
| `publish` fails in `verify-release.sh`         | Artifact handoff incomplete or tampered; inspect the `dist-*` artifacts, re-run the build legs. |
| Release created but assets missing             | `fail_on_unmatched_files` should prevent this; check the file globs in `release.yml`. |
