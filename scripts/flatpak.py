#!/usr/bin/env python3
"""Build a sandboxed offline Flatpak bundle; SDK/runtime must already be installed."""
import argparse
import json
from pathlib import Path
import platform
import subprocess
import tempfile
import tomllib
from package import checksums

ROOT = Path(__file__).resolve().parents[1]
VERSION = tomllib.loads((ROOT / "Cargo.toml").read_text())["package"]["version"]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--out", type=Path, default=ROOT / "dist")
parser.add_argument("--ui-test", action="store_true", help="QA bundle only; never publish this build")
args = parser.parse_args()
assert platform.system() == "Linux", "Flatpak packaging requires Linux"
output = args.out.resolve()
output.mkdir(parents=True, exist_ok=True)
manifest = ROOT / "flatpak/dev.goshapps.calc.yml"
with tempfile.TemporaryDirectory(prefix="gosh-flatpak-") as temporary:
    temporary = Path(temporary)
    if args.ui_test:
        result = subprocess.run(["flatpak-builder", "--show-manifest", str(manifest)], cwd=ROOT, check=True, text=True, capture_output=True)
        data = json.loads(result.stdout)
        module = data["modules"][-1]
        module["build-commands"][2] += " --features ui-test"
        # --show-manifest resolves local paths; retain the original manifest directory.
        manifest = ROOT / "flatpak/.qa-manifest.json"
        manifest.write_text(json.dumps(data), encoding="utf-8")
    try:
        repository = temporary / "repo"
        subprocess.run(["flatpak-builder", "--force-clean", "--disable-rofiles-fuse", "--user", f"--repo={repository}", str(temporary / "build"), str(manifest)], cwd=ROOT, check=True)
        arch = "aarch64" if platform.machine() == "aarch64" else "x86_64"
        bundle = output / f"gosh-calc-{VERSION}-flatpak-{arch}.flatpak"
        subprocess.run(["flatpak", "build-bundle", str(repository), str(bundle), "dev.goshapps.calc", "--runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo"], check=True)
        checksums(output)
    finally:
        if args.ui_test: manifest.unlink(missing_ok=True)
