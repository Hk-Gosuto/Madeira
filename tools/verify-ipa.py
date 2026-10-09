#!/usr/bin/env python3
"""Check the actual IPA payload and compare runtime DLLs byte-for-byte."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import runpy
import struct
import zipfile

validate = runpy.run_path(str(Path(__file__).with_name("fetch-vcruntime.py")))["validate"]


def verify(read):
    info = plistlib.loads(read("Info.plist"))
    binary = read(info["CFBundleExecutable"])
    if struct.unpack_from("<II", binary)[0:2] != (0xfeedfacf, 0x100000c):
        raise ValueError("Madeira must be an ARM64 Mach-O executable")
    helper = plistlib.loads(read("PlugIns/MadeiraJITHelper.appex/Info.plist"))
    read("PlugIns/MadeiraJITHelper.appex/" + helper["CFBundleExecutable"])
    read("Frameworks/StikJIT.framework/StikJIT")
    read("d3d12/libmetalirconverter.dylib")
    read("arm64ec-windows/dockhost.exe")
    read("i386-windows/kernel32.dll")
    read("aarch64-windows/xtajit.dll")
    manifest = json.loads(read("x86_64-vcruntime/manifest.json"))
    read("x86_64-vcruntime/LICENSE.rtf")
    if len(manifest["dlls"]) != 12:
        raise ValueError("Expected all twelve Visual C++ runtime DLLs")
    for name, digest in manifest["dlls"].items():
        data = read("x86_64-vcruntime/" + name)
        validate(data)
        if hashlib.sha256(data).hexdigest() != digest:
            raise ValueError(f"Packaged DLL differs from Microsoft payload: {name}")
    print("Verified ARM64 app, JIT helper, graphics, Dock, WoW64 and 12 original signed x64 DLLs")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("--app", action="store_true")
    args = parser.parse_args()
    if args.app:
        verify(lambda name: (args.path / name).read_bytes())
    else:
        with zipfile.ZipFile(args.path) as archive:
            corrupt = archive.testzip()
            if corrupt:
                raise ValueError(f"Corrupt IPA entry: {corrupt}")
            verify(lambda name: archive.read("Payload/Madeira.app/" + name))


if __name__ == "__main__":
    main()
