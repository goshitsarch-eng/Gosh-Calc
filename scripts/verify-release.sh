#!/usr/bin/env bash
# Verify a Gosh Calc release artifact set before publishing.
#
# Usage:
#   scripts/verify-release.sh --version 0.1.0 --dir dist [--arch x86_64]
#
# Without --arch the full set (x86_64 + aarch64) is required. Checks, per
# artifact: exact naming, existence, non-zero size, tarball integrity plus the
# embedded binary's architecture via file(1); then checksum coverage (every
# expected file listed in SHA256SUMS or a SHA256SUMS-<arch>.txt fragment,
# SHA256SUMS matching the expected set exactly when present) and
# `sha256sum -c` over every checksum file present.
set -euo pipefail

BIN=gosh-calc
VERSION=""
DIR=""
ONLY_ARCH=""

usage() {
    sed -n '2,12p' "$0"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
        --dir) DIR="${2:?--dir needs a value}"; shift 2 ;;
        --arch) ONLY_ARCH="${2:?--arch needs a value}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "verify-release: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$VERSION" ] || { echo "verify-release: --version is required" >&2; exit 2; }
[ -n "$DIR" ] || { echo "verify-release: --dir is required" >&2; exit 2; }
[ -d "$DIR" ] || { echo "verify-release: not a directory: $DIR" >&2; exit 1; }

if [ -n "$ONLY_ARCH" ]; then
    case "$ONLY_ARCH" in
        x86_64|aarch64) ARCHES=("$ONLY_ARCH") ;;
        *) echo "verify-release: unsupported --arch '$ONLY_ARCH'" >&2; exit 2 ;;
    esac
else
    ARCHES=(x86_64 aarch64)
fi

token_for() {
    case "$1" in
        x86_64) echo "x86-64" ;;
        aarch64) echo "aarch64" ;;
    esac
}

fail=0
complain() { echo "verify-release: FAIL: $*" >&2; fail=1; }

EXPECTED=()
for ARCH in "${ARCHES[@]}"; do
    TARBALL="$BIN-$VERSION-$ARCH.tar.gz"
    FLATPAK="$BIN-$VERSION-$ARCH.flatpak"
    EXPECTED+=("$TARBALL" "$FLATPAK")

    for f in "$TARBALL" "$FLATPAK"; do
        if [ ! -f "$DIR/$f" ]; then
            complain "missing required file: $f"
        elif [ ! -s "$DIR/$f" ]; then
            complain "zero-size file: $f"
        fi
    done

    # Tarball integrity + embedded binary arch.
    if [ -s "$DIR/$TARBALL" ]; then
        if ! tar tzf "$DIR/$TARBALL" >/dev/null 2>&1; then
            complain "corrupt tarball: $TARBALL"
        elif ! tar tzf "$DIR/$TARBALL" 2>/dev/null | grep -x "$BIN-$VERSION-$ARCH/$BIN" >/dev/null; then
            complain "tarball $TARBALL lacks $BIN-$VERSION-$ARCH/$BIN"
        else
            TMP="$(mktemp -d -t gosh-calc-verify.XXXXXX)"
            tar xzf "$DIR/$TARBALL" -C "$TMP" "$BIN-$VERSION-$ARCH/$BIN"
            WANT="$(token_for "$ARCH")"
            if ! file "$TMP/$BIN-$VERSION-$ARCH/$BIN" | grep "$WANT" >/dev/null; then
                complain "arch mismatch in $TARBALL: $(file "$TMP/$BIN-$VERSION-$ARCH/$BIN") (want '$WANT')"
            else
                echo "verify-release: arch OK ($ARCH): $(file -b "$TMP/$BIN-$VERSION-$ARCH/$BIN")"
            fi
            rm -rf "$TMP"
        fi
    fi
done

# Checksum files: at least one must exist; every expected file must be
# covered; SHA256SUMS (the published file) must list exactly the set.
shopt -s nullglob
CKFILES=("$DIR"/SHA256SUMS-*.txt)
shopt -u nullglob
[ -f "$DIR/SHA256SUMS" ] && CKFILES+=("$DIR/SHA256SUMS")
if [ "${#CKFILES[@]}" -eq 0 ]; then
    complain "no checksum file (SHA256SUMS or SHA256SUMS-<arch>.txt) in $DIR"
else
    for f in "${EXPECTED[@]}"; do
        if [ -f "$DIR/$f" ]; then
            covered=0
            for ck in "${CKFILES[@]}"; do
                if awk -v want="$f" '$2 == want { found=1 } END { exit !found }' "$ck"; then
                    covered=1
                    break
                fi
            done
            [ "$covered" -eq 1 ] || complain "no checksum entry for $f"
        fi
    done
    if [ -f "$DIR/SHA256SUMS" ]; then
        LISTED="$(awk '{print $2}' "$DIR/SHA256SUMS" | sort)"
        WANT_LIST="$(printf '%s\n' "${EXPECTED[@]}" | sort)"
        if [ "$LISTED" != "$WANT_LIST" ]; then
            complain "SHA256SUMS does not match the expected set; listed: $(echo "$LISTED" | tr '\n' ' ')"
        fi
    fi
    for ck in "${CKFILES[@]}"; do
        if ( cd "$DIR" && sha256sum -c "$(basename "$ck")" >/dev/null ); then
            echo "verify-release: checksums OK: $(basename "$ck")"
        else
            complain "$(basename "$ck") failed 'sha256sum -c'"
        fi
    done
fi

if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "verify-release: PASS: ${#EXPECTED[@]} file(s), version $VERSION"
