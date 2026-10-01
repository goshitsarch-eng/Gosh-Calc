#!/usr/bin/env python3
"""Run the real desktop UI suite (binary built with --features ui-test)."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("binary", type=Path, nargs="?")
parser.add_argument("--flatpak", action="store_true")
args = parser.parse_args()
if not args.flatpak and not args.binary:
    parser.error("provide a binary or --flatpak")
binary = args.binary.resolve() if args.binary else None
with tempfile.TemporaryDirectory(prefix="gosh-calc-Δ-") as temporary:
    root = Path(temporary)
    result_path = root / "outcome"
    environment = os.environ.copy()
    environment.update(GOSH_CALC_UI_TEST="1", GOSH_CALC_UI_TEST_RESULT=str(result_path), GOSH_CALC_CONFIG_DIR=str(root / "config"))
    if os.name != "nt":
        environment["XDG_CONFIG_HOME"] = str(root / "xdg")
    if args.flatpak:
        # A narrow scratch-directory grant is only used by QA. The production
        # manifest has no filesystem grant and uses its app-scoped XDG storage.
        command = ["flatpak", "run", f"--filesystem={root}", "--env=GOSH_CALC_UI_TEST=1", f"--env=GOSH_CALC_UI_TEST_RESULT={result_path}", f"--env=GOSH_CALC_CONFIG_DIR={root / 'config'}", "dev.goshapps.calc"]
    else:
        command = [str(binary)]
    run = subprocess.run(command, env=environment, text=True, capture_output=True, timeout=120)
    print(run.stdout, end="")
    if run.returncode != 0 or not result_path.is_file() or result_path.read_text() != "0":
        print(run.stderr)
        raise SystemExit(f"Desktop suite failed (process exit {run.returncode}); a live process alone is not a passing test.")
    reports = [json.loads(line.split("=", 1)[1]) for line in run.stdout.splitlines() if line.startswith("DESKTOP_TEST_RESULT=")]
    if len(reports) != 1 or not reports[0].get("passed") or not reports[0].get("checks"):
        raise SystemExit("Missing or ambiguous desktop suite report")
    saved = json.loads((root / "config/settings.json").read_text())
    if saved["mode"] != "Standard" or saved["theme"] != "system" or saved["history"]:
        raise SystemExit("Final durable settings did not flush before exit")
    print(f"Desktop suite passed: {len(reports[0]['checks'])} checks")
