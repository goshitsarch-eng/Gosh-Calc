#!/usr/bin/env python3
"""Reproduce the CI checks; --core needs no desktop system libraries."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--core", action="store_true")
args = parser.parse_args()
commands = [["cargo", "fmt", "--check"]]
features = ["--no-default-features"] if args.core else ["--all-features"]
commands += [["cargo", "clippy", "--locked", "--all-targets", *features, "--", "-D", "warnings"],
             ["cargo", "test", "--locked", *features]]
if not args.core:
    commands += [["cargo", "build", "--locked"],
                 ["cargo", "test", "--release", "--locked", "--test", "glib_regression"]]
for command in commands:
    print("Running " + " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, check=True)
