#!/usr/bin/env python3
"""Package an already-built native release executable; no cross-compilation."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile
import tomllib
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
VERSION = tomllib.loads((PROJECT / "Cargo.toml").read_text())["package"]["version"]
APP_ID = "dev.goshapps.calc"

def msi_version(version):
    """Reserve 100 numeric build slots per SemVer patch for ordered previews."""
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta|rc)\.(\d+))?", version)
    if not match: raise ValueError("MSI supports stable or alpha.N/beta.N/rc.N versions")
    major, minor, patch = map(int, match.group(1,2,3))
    phase, sequence = match.group(4,5)
    offset = 99
    if phase:
        sequence = int(sequence)
        if not 1 <= sequence <= 29: raise ValueError("MSI preview sequence must be between 1 and 29")
        offset = {"alpha":0,"beta":30,"rc":60}[phase] + sequence
    build = patch * 100 + offset
    if major > 255 or minor > 255 or build > 65535: raise ValueError("Version exceeds MSI numeric limits")
    return f"{major}.{minor}.{build}"

def checksums(directory):
    files = sorted(p for p in directory.iterdir() if p.is_file() and p.suffix in {".gz", ".zip", ".msi", ".flatpak"})
    with (directory / "SHA256SUMS").open("w", encoding="ascii", newline="\n") as stream:
        for path in files:
            with path.open("rb") as artifact:
                digest = hashlib.file_digest(artifact, "sha256").hexdigest()
            stream.write(f"{digest}  {path.name}\n")

def package(binary, output, arch):
    output.mkdir(parents=True, exist_ok=True)
    system = platform.system().lower()
    stem = f"gosh-calc-{VERSION}-{system}-{arch}"
    with tempfile.TemporaryDirectory(prefix="gosh-package-") as temporary:
        temporary = Path(temporary)
        if system == "darwin":
            bundle = temporary / "Gosh Calc.app" / "Contents"
            (bundle / "MacOS").mkdir(parents=True)
            (bundle / "Resources").mkdir()
            shutil.copy2(binary, bundle / "MacOS" / "gosh-calc")
            shutil.copy2(PROJECT / "resources/icon.icns", bundle / "Resources/icon.icns")
            metadata = {"CFBundleName":"Gosh Calc", "CFBundleDisplayName":"Gosh Calc", "CFBundleIdentifier":APP_ID, "CFBundleExecutable":"gosh-calc", "CFBundlePackageType":"APPL", "CFBundleIconFile":"icon.icns", "CFBundleShortVersionString":VERSION.split("-")[0], "CFBundleVersion":VERSION.split("-")[0], "NSHighResolutionCapable":True, "LSMinimumSystemVersion":"11.0", "NSHumanReadableCopyright":"Copyright © 2026 goshitsarch-eng"}
            with (bundle / "Info.plist").open("wb") as stream: plistlib.dump(metadata,stream)
            identity = os.environ.get("MACOS_SIGNING_IDENTITY", "-")
            signing = ["codesign","--force","--deep","--sign",identity]
            if identity != "-": signing.extend(["--options","runtime","--timestamp"])
            subprocess.run(signing + [str(bundle.parent)],check=True)
            subprocess.run(["ditto","-c","-k","--sequesterRsrc","--keepParent",str(bundle.parent),str(output / f"{stem}.zip")],check=True)
            if os.environ.get("MACOS_NOTARY_PROFILE"):
                subprocess.run(["xcrun","notarytool","submit",str(output / f"{stem}.zip"),"--keychain-profile",os.environ["MACOS_NOTARY_PROFILE"],"--wait"],check=True)
                subprocess.run(["xcrun","stapler","staple",str(bundle.parent)],check=True)
                (output / f"{stem}.zip").unlink()
                subprocess.run(["ditto","-c","-k","--sequesterRsrc","--keepParent",str(bundle.parent),str(output / f"{stem}.zip")],check=True)
        elif system == "windows":
            numeric_version = msi_version(VERSION)
            subprocess.run(["wix","build",str(PROJECT / "packaging/windows/main.wxs"),"-arch","x64","-d",f"Version={numeric_version}","-d",f"SourceDir={binary.parent}","-d",f"ProjectDir={PROJECT}","-o",str(output / f"{stem}.msi")],check=True)
            with zipfile.ZipFile(output / f"{stem}.zip","w",zipfile.ZIP_DEFLATED) as archive:
                archive.write(binary,"gosh-calc.exe")
                archive.write(PROJECT / "LICENSE","LICENSE")
        elif system == "linux":
            folder = temporary / stem
            folder.mkdir()
            shutil.copy2(binary,folder / "gosh-calc")
            for file in ["README.md","LICENSE"]: shutil.copy2(PROJECT / file,folder / file)
            for file in [f"{APP_ID}.desktop",f"{APP_ID}.metainfo.xml","icon.png"]: shutil.copy2(PROJECT / "resources" / file,folder / file)
            with tarfile.open(output / f"{stem}.tar.gz","w:gz") as archive: archive.add(folder,arcname=stem)
        else:
            raise ValueError(f"Unsupported OS: {system}")
    checksums(output)

if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary",type=Path)
    parser.add_argument("--out",type=Path,default=PROJECT / "dist")
    parser.add_argument("--arch",choices=["x86_64","aarch64"],default="aarch64" if platform.machine().lower() in {"arm64","aarch64"} else "x86_64")
    args=parser.parse_args()
    package((args.binary or PROJECT / "target/release" / ("gosh-calc.exe" if os.name=="nt" else "gosh-calc")).resolve(),args.out.resolve(),args.arch)
