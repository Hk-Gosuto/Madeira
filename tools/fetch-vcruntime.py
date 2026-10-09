#!/usr/bin/env python3
"""Extract unmodified, signed x64 runtime DLLs from Microsoft's pinned installer."""
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
URL = ("https://download.visualstudio.microsoft.com/download/pr/"
       "bd1c8d9d-ba95-4eee-bc6e-df1fcc876373/"
       "CC0FF0EB1DC3F5188AE6300FAEF32BF5BEEBA4BDD6E8E445A9184072096B713B/"
       "VC_redist.x64.exe")
SHA256 = "cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b"
DLLS = """concrt140 msvcp140 msvcp140_1 msvcp140_2 msvcp140_atomic_wait
msvcp140_codecvt_ids vcamp140 vccorlib140 vcomp140 vcruntime140
vcruntime140_1 vcruntime140_threads""".split()


def validate(data):
    """Reject the ARM64 payload and missing/truncated Authenticode certificates."""
    if data[:2] != b"MZ":
        raise ValueError("not a PE file")
    pe = struct.unpack_from("<I", data, 0x3c)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("invalid PE signature")
    if struct.unpack_from("<H", data, pe + 4)[0] != 0x8664:
        raise ValueError("expected x86-64 DLL")
    if struct.unpack_from("<H", data, pe + 24)[0] != 0x20b:
        raise ValueError("expected PE32+")
    offset, size = struct.unpack_from("<II", data, pe + 24 + 112 + 4 * 8)
    if not offset or size < 8 or offset + size > len(data):
        raise ValueError("missing/truncated Authenticode certificate")
    length, revision, kind = struct.unpack_from("<IHH", data, offset)
    if not 8 <= length <= size or revision != 0x200 or kind != 2:
        raise ValueError("invalid Authenticode certificate")


def main():
    sevenzip = shutil.which("7zz") or shutil.which("7z")
    if not sevenzip:
        raise SystemExit("Install sevenzip first: brew install sevenzip")
    output = ROOT / "app/Madeira/x86_64-vcruntime"
    with tempfile.TemporaryDirectory(prefix="madeira-vcrt-") as tmp:
        tmp = Path(tmp)
        installer = tmp / "VC_redist.x64.exe"
        subprocess.run(["curl", "--fail", "--location", "--retry", "3", URL,
                        "--output", str(installer)], check=True)
        data = installer.read_bytes()
        if hashlib.sha256(data).hexdigest() != SHA256:
            raise SystemExit("Microsoft installer SHA-256 mismatch")
        # WiX Burn has two attached CABs. 7-Zip opens only the first (UI);
        # extract the bounded CAB streams, then their nested runtime CABs.
        position = 0
        cabinets = []
        while True:
            position = data.find(b"MSCF\0\0\0\0", position)
            if position < 0:
                break
            size = struct.unpack_from("<I", data, position + 8)[0]
            if size >= 36 and position + size <= len(data):
                cab = tmp / f"container-{position}.cab"
                cab.write_bytes(data[position:position + size])
                cabinets.append(cab)
            position += 8
        candidates = {}
        for cab in cabinets:
            folder = cab.with_suffix("")
            subprocess.run([sevenzip, "x", "-y", str(cab), f"-o{folder}"],
                           check=True, stdout=subprocess.DEVNULL)
            for payload in folder.iterdir():
                if payload.is_file() and payload.read_bytes()[:4] == b"MSCF":
                    nested = folder / (payload.name + "-extracted")
                    subprocess.run([sevenzip, "x", "-y", str(payload), f"-o{nested}"],
                                   check=True, stdout=subprocess.DEVNULL)
                    for path in nested.iterdir():
                        name = path.name.removesuffix("_amd64")
                        if name in [dll + ".dll" for dll in DLLS]:
                            blob = path.read_bytes()
                            try:
                                validate(blob)
                            except ValueError:
                                continue
                            if name in candidates and candidates[name] != blob:
                                raise SystemExit(f"Conflicting x64 payloads for {name}")
                            candidates[name] = blob
        missing = sorted(set(dll + ".dll" for dll in DLLS) - candidates.keys())
        if missing:
            raise SystemExit(f"Missing signed x64 DLLs: {missing}")
        output.mkdir(parents=True, exist_ok=True)
        # Preserve Microsoft's installer license next to its runtime files.
        license_files = list(tmp.glob("container-*/u4"))
        if len(license_files) != 1 or not license_files[0].read_bytes().startswith(b"{\\rtf"):
            raise SystemExit("Missing Microsoft license from pinned installer")
        shutil.copyfile(license_files[0], output / "LICENSE.rtf")
        for name, blob in candidates.items():
            (output / name).write_bytes(blob)
        manifest = {"version": "14.44.35211.0", "url": URL, "installer_sha256": SHA256,
                    "dlls": {name: hashlib.sha256(blob).hexdigest()
                             for name, blob in sorted(candidates.items())}}
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"Staged {len(candidates)} signed, unmodified x64 DLLs in {output}")


if __name__ == "__main__":
    main()
