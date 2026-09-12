# Releasing Gosh Calc

Short maintainer runbook. Background: [CI architecture](release/CI-ARCHITECTURE.md),
[packaging](release/PACKAGING.md), [release policy](release/RELEASES.md).

## Cut a release

1. Bump the version in one commit:
   - `Cargo.toml` `package.version`
   - `resources/dev.goshapps.calc.metainfo.xml` — new `<release version="..." date="...">` entry
   - If dependencies changed: `cargo build` (updates `Cargo.lock`), then regenerate
     `python3 flatpak/flatpak-cargo-generator.py Cargo.lock -o flatpak/cargo-sources.json`
2. Run the full local gate: `scripts/verify.sh`
3. Optionally dry-run packaging for your arch:
   `scripts/package-release.sh --version X.Y.Z --arch "$(uname -m)" --out /tmp/gosh-dist`
   (packaging requires a clean tree)
4. Commit, then tag and push:
   ```sh
   git tag -a vX.Y.Z -m "gosh-calc vX.Y.Z"
   git push origin main vX.Y.Z
   ```
5. Watch the `Release` workflow on the tag. `gate` -> both `build`
   legs -> `publish`, which creates the GitHub release with the four
   artifacts plus `SHA256SUMS`.
6. Sanity-check the published release: download `SHA256SUMS` plus one
   tarball and run `sha256sum -c SHA256SUMS`.

Pre-releases: tag `vX.Y.Z-rc.1` (or `-beta`, ...). The pipeline marks
the GitHub release as a pre-release automatically; artifact names carry
the full `X.Y.Z-rc.1` version.

## Rules

- Tags are `v<Cargo version>[-suffix]`, and the tag stem must equal
  `Cargo.toml` (enforced by the gate). Never publish from a branch
  push — `release.yml` is tag-only, and `ci.yml` never publishes.
- A failed run before `publish` publishes nothing: fix forward and
  re-run the workflow. Never force-move a tag with a published
  release; cut a new version instead.
