# Packaging

Each release ships four artifacts plus a checksum file, built natively —
x86_64 binaries on an x86_64 runner, aarch64 binaries on an aarch64
runner. There is no cross-compilation.

## Artifact inventory

For version `X.Y.Z` (or `X.Y.Z-suffix` for pre-releases):

| File                              | Contents                                   |
| --------------------------------- | ------------------------------------------ |
| `gosh-calc-X.Y.Z-x86_64.tar.gz`   | Portable tarball, x86_64 binary            |
| `gosh-calc-X.Y.Z-x86_64.flatpak`  | Single-file Flatpak bundle, x86_64         |
| `gosh-calc-X.Y.Z-aarch64.tar.gz`  | Portable tarball, aarch64 binary           |
| `gosh-calc-X.Y.Z-aarch64.flatpak` | Single-file Flatpak bundle, aarch64        |
| `SHA256SUMS`                      | SHA-256 of the four files above            |

Per-arch `SHA256SUMS-<arch>.txt` fragments exist only as CI handoff
files between the build legs and `publish`; they are not release assets.

## Tarball layout

`gosh-calc-X.Y.Z-<arch>.tar.gz` extracts to one top directory:

```text
gosh-calc-X.Y.Z-<arch>/
  gosh-calc                       # stripped release binary
  dev.goshapps.calc.desktop       # desktop entry
  dev.goshapps.calc.metainfo.xml  # AppStream metainfo
  dev.goshapps.calc.svg           # icon
  README.md
  LICENSE
```

The app needs no other runtime assets: translations are compiled in
(`src/i18n.rs` via `RustEmbed`), settings use the cosmic-config file
backend. At runtime the binary dynamically loads system GUI libraries
(Wayland client, xkbcommon, X11 as configured); any modern desktop has
these.

## Flatpak bundle

Built by `flatpak-builder` from `flatpak/dev.goshapps.calc.yml`
(Freedesktop 25.08, rust-stable SDK extension, offline vendored cargo
sources) and exported with `flatpak build-bundle` as an unsigned
single-file bundle installable with:

```sh
flatpak install --user gosh-calc-X.Y.Z-<arch>.flatpak
```

Sandbox grants stay minimal (Wayland, fallback X11, IPC, DRI) per the
manifest. After any `Cargo.lock` change, regenerate the vendored
sources or the offline build breaks:

```sh
python3 flatpak/flatpak-cargo-generator.py Cargo.lock -o flatpak/cargo-sources.json
```

## Architecture mapping

Native runners mean `cargo build --release` needs no `--target`; the
architecture is verified after the fact with `file(1)`:

| `--arch` | Host (`uname -m`) | `file(1)` must contain |
| -------- | ----------------- | ---------------------- |
| `x86_64` | `x86_64`          | `x86-64`               |
| `aarch64`| `aarch64`         | `aarch64`              |

`package-release.sh` refuses to run when `--arch` does not match the
host, and `verify-release.sh` re-checks the `file(1)` token on the
binary extracted from each tarball. The Flatpak bundle is assured by
construction (built natively on the same runner as its arch-verified
tarball sibling) plus presence/size/naming checks.

## Checksums

Each build leg writes `SHA256SUMS-<arch>.txt` over its own artifacts;
`publish` regenerates the single published `SHA256SUMS` from the
downloaded files and `verify-release.sh` enforces exact-set coverage
plus `sha256sum -c`. To verify a download:

```sh
sha256sum -c SHA256SUMS
```

## Local packaging

Requirements: stable Rust, `file`, `sha256sum`, `tar`, `strip`, git,
plus `flatpak`, `flatpak-builder`, `eu-strip` (from `elfutils` —
flatpak-builder needs it for its debug-strip finish phase),
an SVG loader for `appstreamcli compose` (`librsvg2-common` on
Debian/Ubuntu — without it the compose step fails with
`file-read-error` / `filters-but-no-output`), and the
Freedesktop 25.08 platform/SDK with the rust-stable extension for the
bundle:

```sh
flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y flathub \
  org.freedesktop.Platform//25.08 \
  org.freedesktop.Sdk//25.08 \
  org.freedesktop.Sdk.Extension.rust-stable//25.08
```

Package your host arch (tree must be clean, version must match
`Cargo.toml`):

```sh
ARCH="$(uname -m)" # x86_64 or aarch64 on Linux
scripts/package-release.sh --version 0.1.0 --arch "$ARCH" --out dist
scripts/verify-release.sh --version 0.1.0 --dir dist --arch "$ARCH"
```

Pass `--no-flatpak` to skip the bundle step
for a quick tarball-only iteration; note the result is a partial set
and full `verify-release.sh` (both arches) will not pass on it.
Artifacts go to `dist/`, which is gitignored.
