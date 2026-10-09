#!/bin/bash
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
cd "$R"
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-3}"
# DXMT uses LLVM 15 at the exact commit in the reproducibility record.
cmake -S toolchains/llvm-project/llvm -B toolchains/llvm-host-build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD= \
    -DLLVM_ENABLE_PROJECTS= -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF
cmake --build toolchains/llvm-host-build --target llvm-tblgen
cmake -S toolchains/llvm-project/llvm -B toolchains/llvm-ios-build -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_MACOSX_BUNDLE=OFF \
    -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_BUILD_TYPE=Release -DLLVM_HOST_TRIPLE=arm64-apple-ios17.0 \
    -DLLVM_DEFAULT_TARGET_TRIPLE=arm64-apple-ios17.0 -DLLVM_TARGET_ARCH=host \
    -DLLVM_TARGETS_TO_BUILD= -DLLVM_ENABLE_PROJECTS= -DLLVM_BUILD_TOOLS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_TABLEGEN="$R/toolchains/llvm-host-build/bin/llvm-tblgen"
cmake --build toolchains/llvm-ios-build

