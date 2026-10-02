#!/usr/bin/env python3
"""Generate offline registry sources from Cargo.lock without extra Python deps.

Every crate archive is checked against the checksum recorded by Cargo. This
application intentionally has no git dependencies; reject those rather than
silently producing an incomplete source list.
"""
import argparse
import json
from pathlib import Path
import tomllib

def generate(lock):
    sources = []
    for package in lock["package"]:
        if "source" not in package:
            continue
        if package["source"] != "registry+https://github.com/rust-lang/crates.io-index":
            raise ValueError(f"Unsupported package source: {package['source']}")
        name, version, checksum = package["name"], package["version"], package["checksum"]
        destination = f"cargo/vendor/{name}-{version}"
        sources.extend([
            {"type": "archive", "archive-type": "tar-gzip", "url": f"https://static.crates.io/crates/{name}/{name}-{version}.crate", "sha256": checksum, "dest": destination},
            {"type": "inline", "contents": json.dumps({"package": checksum, "files": {}}), "dest": destination, "dest-filename": ".cargo-checksum.json"},
        ])
    sources.append({"type": "inline", "dest": "cargo", "dest-filename": "config.toml", "contents": '[source.crates-io]\nreplace-with = "vendored-sources"\n[source.vendored-sources]\ndirectory = "cargo/vendor"\n'})
    return sources

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lock", type=Path)
    parser.add_argument("-o", "--output", required=True, type=Path)
    args = parser.parse_args()
    with args.lock.open("rb") as stream:
        result = generate(tomllib.load(stream))
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
