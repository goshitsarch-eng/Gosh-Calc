#!/usr/bin/env python3
"""Validate artifact contents, architecture and exact SHA256SUMS coverage."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import struct
import tarfile
import zipfile

ARCHES = {"x86_64": 62, "aarch64": 183}

def binary_arch(data, system, arch):
    if system == "linux":
        assert data[:4] == b"\x7fELF", "not an ELF executable"
        assert data[4:6] == b"\x02\x01", "expected little-endian 64-bit ELF"
        assert struct.unpack_from("<H", data, 18)[0] == ARCHES[arch], "ELF architecture mismatch"
    elif system == "windows":
        assert data[:2] == b"MZ", "not a PE executable"
        offset = struct.unpack_from("<I", data, 60)[0]
        assert data[offset:offset+4] == b"PE\0\0", "invalid PE header"
        assert struct.unpack_from("<H", data, offset+4)[0] == 0x8664, "expected Windows x86_64"
    else:
        assert data[:4] == b"\xcf\xfa\xed\xfe", "expected 64-bit Mach-O"
        expected = 0x0100000C if arch == "aarch64" else 0x01000007
        assert struct.unpack_from("<I", data, 4)[0] == expected, "Mach-O architecture mismatch"

def verify(directory, version, full=False):
    manifest = directory / "SHA256SUMS"
    entries = {}
    for line in manifest.read_text(encoding="ascii").splitlines():
        digest, name = line.split("  ", 1)
        assert len(digest) == 64 and all(c in "0123456789abcdef" for c in digest), "invalid SHA-256"
        assert Path(name).name == name and name not in entries, "unsafe or duplicate checksum name"
        entries[name] = digest
    artifacts = {p.name for p in directory.iterdir() if p.is_file() and p.suffix in {".gz", ".zip", ".msi", ".flatpak"}}
    assert artifacts and set(entries) == artifacts, "checksum coverage differs from artifact set"
    if full:
        expected = {f"gosh-calc-{version}-windows-x86_64.{suffix}" for suffix in ["msi", "zip"]}
        for arch in ARCHES:
            expected.update({f"gosh-calc-{version}-linux-{arch}.tar.gz", f"gosh-calc-{version}-darwin-{arch}.zip", f"gosh-calc-{version}-flatpak-{arch}.flatpak"})
        assert artifacts == expected, f"release set differs: {artifacts.symmetric_difference(expected)}"
    for name, digest in entries.items():
        path = directory / name
        assert path.stat().st_size > 0, f"empty artifact: {name}"
        with path.open("rb") as stream:
            assert hashlib.file_digest(stream, "sha256").hexdigest() == digest, f"checksum mismatch: {name}"
        assert name.startswith(f"gosh-calc-{version}-"), f"wrong artifact version: {name}"
        arch = "aarch64" if "-aarch64." in name else "x86_64"
        if name.endswith(".tar.gz"):
            stem = name.removesuffix(".tar.gz")
            with tarfile.open(path) as archive:
                members = archive.getmembers()
                assert all(not m.name.startswith("/") and ".." not in Path(m.name).parts and not (m.issym() or m.islnk()) for m in members), "unsafe tar members"
                executable = archive.getmember(f"{stem}/gosh-calc")
                assert executable.mode & 0o111, "Linux executable permission missing"
                binary_arch(archive.extractfile(executable).read(4096), "linux", arch)
                assert f"{stem}/LICENSE" in archive.getnames()
        elif name.endswith(".zip"):
            with zipfile.ZipFile(path) as archive:
                assert archive.testzip() is None, "corrupt zip member"
                assert all(not n.startswith("/") and ".." not in Path(n).parts for n in archive.namelist()), "unsafe zip members"
                if "-windows-" in name:
                    binary_arch(archive.read("gosh-calc.exe"), "windows", arch)
                    assert "LICENSE" in archive.namelist()
                else:
                    prefix = "Gosh Calc.app/Contents/"
                    info = plistlib.loads(archive.read(prefix + "Info.plist"))
                    assert info["CFBundleIdentifier"] == "dev.goshapps.calc"
                    assert info["CFBundleShortVersionString"] == version.split("-")[0]
                    binary_arch(archive.read(prefix + "MacOS/gosh-calc"), "darwin", arch)
                    assert prefix + "Resources/icon.icns" in archive.namelist()
        elif name.endswith(".msi"):
            with path.open("rb") as stream:
                assert stream.read(8) == bytes.fromhex("d0cf11e0a1b11ae1"), "not an MSI compound document"
        print(f"Verified {name}")
    return len(entries)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--dir", type=Path, default=Path("dist"))
    parser.add_argument("--full", action="store_true")
    args = parser.parse_args()
    print(f"Verified {verify(args.dir, args.version, args.full)} artifacts")
