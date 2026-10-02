#!/usr/bin/env python3
"""Require an exact tag/Cargo/AppStream match and a current offline source list."""
import json
import os
from pathlib import Path
import subprocess
import tomllib
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
version = tomllib.loads((root / "Cargo.toml").read_text())["package"]["version"]
assert os.environ["TAG"] == "v" + version, "tag must exactly match Cargo version including prerelease"
assert ET.parse(root / "resources/dev.goshapps.calc.metainfo.xml").find("./releases/release").get("version") == version
before = (root / "flatpak/cargo-sources.json").read_bytes()
subprocess.run(["python3", "flatpak/flatpak-cargo-generator.py", "Cargo.lock", "-o", "flatpak/cargo-sources.json"], cwd=root, check=True)
assert (root / "flatpak/cargo-sources.json").read_bytes() == before, "regenerate offline sources from Cargo.lock"
json.loads(before)
with Path(os.environ["GITHUB_OUTPUT"]).open("a") as stream:
    stream.write(f"version={version}\nprerelease={'true' if '-' in version else 'false'}\n")
