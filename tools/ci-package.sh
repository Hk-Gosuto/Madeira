#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/xcode-derived/Build/Products/Debug-iphoneos/Madeira.app
OUT=build/ipa
mkdir -p "$OUT/Payload"
ditto "$APP" "$OUT/Payload/Madeira.app"
# Match upstream release packaging: Mono is downloaded by the app on demand.
rm -rf "$OUT/Payload/Madeira.app/wine-mono"
python3 tools/verify-ipa.py --app "$OUT/Payload/Madeira.app"
(cd "$OUT" && zip -qry Madeira-vcruntime.ipa Payload)
python3 tools/verify-ipa.py "$OUT/Madeira-vcruntime.ipa"
(cd "$OUT" && shasum -a 256 Madeira-vcruntime.ipa > SHA256SUMS)
cp app/Madeira/x86_64-vcruntime/manifest.json "$OUT/vcruntime-manifest.json"
{
    git rev-parse HEAD
    git submodule status --recursive
    xcodebuild -version
    xcrun --sdk iphoneos --show-sdk-version
    echo 'Configuration: Debug; signing: unsigned (sideload and sign with your Apple ID)'
    echo 'LLVM: 8dfdcc7b7bf66834a761bd8de445840ef68e4d1a'
    git -C research/freetype rev-parse HEAD
} > "$OUT/build-info.txt"
