#!/usr/bin/env bash
# Build and package one native release artifact set for Gosh Calc.
#
# Usage:
#   scripts/package-release.sh --version 0.1.0 --arch x86_64 [--out dist] [--no-flatpak]
#
# Builds the release binary natively, verifies its architecture with file(1),
# assembles the portable tarball, builds the Flatpak bundle (unless
# --no-flatpak), and writes a per-arch SHA256SUMS fragment. Cross-building is
# not supported: --arch must match the host (`uname -m`).
#
# Layout, naming, and tool requirements: docs/release/PACKAGING.md.
set -euo pipefail

APP_ID=dev.goshapps.calc
BIN=gosh-calc
VERSION=""
ARCH=""
OUT=dist
WITH_FLATPAK=1

usage() {
    sed -n '2,14p' "$0"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
        --arch) ARCH="${2:?--arch needs a value}"; shift 2 ;;
        --out) OUT="${2:?--out needs a value}"; shift 2 ;;
        --no-flatpak) WITH_FLATPAK=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "package-release: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$VERSION" ] || { echo "package-release: --version is required" >&2; exit 2; }
[ -n "$ARCH" ] || { echo "package-release: --arch is required" >&2; exit 2; }

case "$ARCH" in
    x86_64)  EXPECT_UNAME=x86_64;  EXPECT_FILE_TOKEN="x86-64" ;;
    aarch64) EXPECT_UNAME=aarch64; EXPECT_FILE_TOKEN="aarch64" ;;
    *) echo "package-release: unsupported --arch '$ARCH' (want x86_64 or aarch64)" >&2; exit 2 ;;
esac

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.+-]+)?$ ]]; then
    echo "package-release: bad --version '$VERSION' (want X.Y.Z[-suffix])" >&2
    exit 2
fi

HOST_ARCH="$(uname -m)"
if [ "$HOST_ARCH" != "$EXPECT_UNAME" ]; then
    echo "package-release: native build only: --arch $ARCH needs $EXPECT_UNAME, host is $HOST_ARCH" >&2
    exit 1
fi

cd "$(dirname "$0")/.."

# --- version consistency: tag stem must equal Cargo.toml, metainfo exact -----
STEM="${VERSION%%-*}"
CARGO_VERSION="$(python3 -c 'import tomllib; print(tomllib.load(open("Cargo.toml","rb"))["package"]["version"])')"
META_VERSION="$(python3 -c 'import xml.etree.ElementTree as ET; print(ET.parse("resources/dev.goshapps.calc.metainfo.xml").getroot().find("./releases/release").get("version"))')"
if [ "$STEM" != "$CARGO_VERSION" ]; then
    echo "package-release: version $VERSION does not match Cargo.toml ($CARGO_VERSION)" >&2
    exit 1
fi
if [ "$META_VERSION" != "$CARGO_VERSION" ]; then
    echo "package-release: metainfo ($META_VERSION) does not match Cargo.toml ($CARGO_VERSION)" >&2
    exit 1
fi

# --- tree must be clean so artifacts match a real commit ----------------------
if [ -n "$(git status --porcelain -- . ':!target')" ]; then
    echo "package-release: working tree is dirty; commit or stash first" >&2
    git status --porcelain -- . ':!target' >&2
    exit 1
fi

# --- tool + source-bundle preflight -------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || { echo "package-release: missing required tool: $1" >&2; exit 1; }; }
need cargo; need file; need sha256sum; need tar; need strip
if [ "$WITH_FLATPAK" -eq 1 ]; then
    need flatpak; need flatpak-builder; need eu-strip
fi
python3 -c 'import json; json.load(open("flatpak/cargo-sources.json"))' \
    || { echo "package-release: flatpak/cargo-sources.json missing or invalid; regenerate it (see CONTRIBUTING.md)" >&2; exit 1; }

# --- build --------------------------------------------------------------------
echo "package-release: cargo build --release ($ARCH, version $VERSION)"
cargo build --release --locked

RELEASE_BIN="target/release/$BIN"
[ -x "$RELEASE_BIN" ] || { echo "package-release: $RELEASE_BIN not found after build" >&2; exit 1; }
if ! file "$RELEASE_BIN" | grep -q "$EXPECT_FILE_TOKEN"; then
    echo "package-release: arch mismatch: $(file "$RELEASE_BIN")" >&2
    echo "package-release: expected file(1) output to contain '$EXPECT_FILE_TOKEN'" >&2
    exit 1
fi
echo "package-release: arch OK: $(file -b "$RELEASE_BIN")"

# --- tarball ------------------------------------------------------------------
mkdir -p "$OUT"
STAGE="$OUT/stage"
TOPDIR="$BIN-$VERSION-$ARCH"
rm -rf "$STAGE/$TOPDIR"
mkdir -p "$STAGE/$TOPDIR"
cp "$RELEASE_BIN" "$STAGE/$TOPDIR/$BIN"
strip "$STAGE/$TOPDIR/$BIN"
cp "resources/$APP_ID.desktop" "$STAGE/$TOPDIR/"
cp "resources/$APP_ID.metainfo.xml" "$STAGE/$TOPDIR/"
cp "resources/icons/hicolor/scalable/apps/$APP_ID.svg" "$STAGE/$TOPDIR/"
cp README.md LICENSE "$STAGE/$TOPDIR/"

TARBALL="$BIN-$VERSION-$ARCH.tar.gz"
rm -f "$OUT/$TARBALL"
tar -czf "$OUT/$TARBALL" -C "$STAGE" "$TOPDIR"
rm -rf "$STAGE"
echo "package-release: wrote $OUT/$TARBALL"

# --- flatpak bundle ------------------------------------------------------------
FLATPAK="$BIN-$VERSION-$ARCH.flatpak"
if [ "$WITH_FLATPAK" -eq 1 ]; then
    WORK="$(mktemp -d -t gosh-calc-flatpak.XXXXXX)"
    trap 'rm -rf "$WORK"' EXIT
    echo "package-release: flatpak-builder ($ARCH)"
    flatpak-builder --force-clean --disable-rofiles-fuse --user \
        --repo="$WORK/repo" "$WORK/build-dir" "flatpak/$APP_ID.yml"
    rm -f "$OUT/$FLATPAK"
    flatpak build-bundle "$WORK/repo" "$OUT/$FLATPAK" "$APP_ID" stable
    echo "package-release: wrote $OUT/$FLATPAK"
fi

# --- per-arch checksums (publish merges these into SHA256SUMS) -----------------
FRAGMENT="SHA256SUMS-$ARCH.txt"
rm -f "$OUT/$FRAGMENT"
(
    cd "$OUT"
    if [ "$WITH_FLATPAK" -eq 1 ]; then
        sha256sum "$TARBALL" "$FLATPAK" > "$FRAGMENT"
    else
        sha256sum "$TARBALL" > "$FRAGMENT"
    fi
)

echo "package-release: done ($ARCH):"
if [ "$WITH_FLATPAK" -eq 1 ]; then
    ls -l "$OUT/$TARBALL" "$OUT/$FLATPAK"
else
    ls -l "$OUT/$TARBALL"
fi
cat "$OUT/$FRAGMENT"
