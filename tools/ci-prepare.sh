#!/bin/bash
# Fetch the non-repository inputs recorded in docs/BUILDING.md.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p toolchains research
TC=llvm-mingw-20260421-ucrt-macos-universal
if [ ! -d "toolchains/$TC" ]; then
    curl -fL --retry 3 "https://github.com/mstorsjo/llvm-mingw/releases/download/20260421/$TC.tar.xz" -o "toolchains/$TC.tar.xz"
    echo "bd85a3975723815cef28dbbd2ca2cb0c926f6b348a12a0453f39f7af273cb3f7  toolchains/$TC.tar.xz" | shasum -a 256 -c -
    tar -xf "toolchains/$TC.tar.xz" -C toolchains
    rm "toolchains/$TC.tar.xz"
fi
if [ ! -d research/freetype ]; then
    git clone --depth 1 --branch VER-2-13-3 https://github.com/freetype/freetype.git research/freetype
fi
if [ ! -d toolchains/llvm-project ]; then
    mkdir toolchains/llvm-project
    git -C toolchains/llvm-project init
    git -C toolchains/llvm-project remote add origin https://github.com/llvm/llvm-project.git
    git -C toolchains/llvm-project fetch --depth 1 origin 8dfdcc7b7bf66834a761bd8de445840ef68e4d1a
    git -C toolchains/llvm-project checkout --detach FETCH_HEAD
fi
python3 tools/fetch-vcruntime.py
