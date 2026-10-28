#!/usr/bin/env bash
# Builds release packages into dist/ using the presets in export_presets.cfg.
# Needs Godot and its matching export templates installed.
# Usage: scripts/export.sh [version]   (defaults to the project version)
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
VERSION="${1:-$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)}"
rm -rf build dist
mkdir -p build/linux-x86_64 build/linux-arm64 build/windows-x86_64 build/macos dist

"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
for preset in "Linux x86_64" "Linux arm64" "Windows x86_64" "macOS universal"; do
  echo "== exporting $preset"
  "$GODOT" --headless --path . --export-release "$preset"
done

package_linux() { # arch dir binary
  local arch=$1 dir=$2 binary=$3 stage="dist/stage-$1"
  rm -rf "$stage" && mkdir -p "$stage/gosh-calc"
  install -m755 "build/$dir/$binary" "$stage/gosh-calc/gosh-calc"
  install -m644 LICENSE THIRD_PARTY_LICENSES.md "$stage/gosh-calc/"
  install -m644 resources/dev.goshapps.calc.desktop resources/dev.goshapps.calc.metainfo.xml "$stage/gosh-calc/"
  install -m644 assets/icon.svg "$stage/gosh-calc/dev.goshapps.calc.svg"
  tar -C "$stage" -czf "dist/gosh-calc-$VERSION-linux-$arch.tar.gz" gosh-calc
  rm -rf "$stage"
}
package_linux x86_64 linux-x86_64 gosh-calc.x86_64
package_linux aarch64 linux-arm64 gosh-calc.arm64

stage=dist/stage-windows && rm -rf "$stage" && mkdir -p "$stage"
cp "build/windows-x86_64/Gosh Calc.exe" LICENSE THIRD_PARTY_LICENSES.md "$stage/"
(cd "$stage" && zip -qr "../gosh-calc-$VERSION-windows-x86_64.zip" .)
rm -rf "$stage"
cp "build/macos/Gosh Calc.zip" "dist/gosh-calc-$VERSION-macos-universal.zip"

(cd dist && sha256sum ./*.tar.gz ./*.zip > SHA256SUMS)
ls -la dist
