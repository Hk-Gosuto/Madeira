#!/bin/bash
# Full Debug iPhone build, including the optional 32-bit guest runtime.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
cd "$R"
export PATH="$R/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin:$(brew --prefix bison)/bin:$(brew --prefix llvm)/bin:$PATH"
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-3}"
export JOBS="$CMAKE_BUILD_PARALLEL_LEVEL"
trap 'find build -type f \( -name "*.err" -o -name "err-*.txt" -o -name "*.log" \) -size +0c -exec tail -n 30 {} \;' ERR

# DXMT uses LLVM 15 at the exact commit in the reproducibility record.
cmake -S toolchains/llvm-project/llvm -B toolchains/llvm-host-build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD= \
    -DLLVM_ENABLE_PROJECTS= -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF
cmake --build toolchains/llvm-host-build --target llvm-tblgen
cmake -S toolchains/llvm-project/llvm -B toolchains/llvm-ios-build -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_BUILD_TYPE=Release -DLLVM_HOST_TRIPLE=arm64-apple-ios17.0 \
    -DLLVM_DEFAULT_TARGET_TRIPLE=arm64-apple-ios17.0 -DLLVM_TARGET_ARCH=host \
    -DLLVM_TARGETS_TO_BUILD= -DLLVM_ENABLE_PROJECTS= -DLLVM_BUILD_TOOLS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_TABLEGEN="$R/toolchains/llvm-host-build/bin/llvm-tblgen"
cmake --build toolchains/llvm-ios-build

bash build/gnutls-ios/build.sh
cp toolchains/gnutls-ios/lib/lib{gmp,nettle,hogweed,gnutls}.a app/Madeira/
bash build/ffmpeg/build.sh
bash build/freetype-ios/build.sh
bash build/fex-ios/build.sh
bash build/fex-arm64ec/build.sh

# The unix scripts consume macOS configure output and widl-generated headers.
mkdir -p wine/build-macos
if [ ! -f wine/build-macos/config.status ]; then
    (cd wine/build-macos && ../configure --without-x --without-freetype --disable-tests --enable-winegstreamer)
fi
make -C wine/build-macos -j"$JOBS" __builddeps__
bash build/wine-pe/build-ntdll.sh
make -C wine/build-arm64ec -j"$JOBS" __builddeps__
bash build/wine-pe/build-modules.sh
bash build/wine-pe/build-modules.sh dcomp ktmw32
bash build/ntdll-unix/build.sh
bash build/wineserver/build.sh
bash build/win32u-unix/build.sh

bash build/dxmt-ios/build.sh
# The upstream incremental script does not create the combined archive on a
# clean checkout. Merge its objects with LLVM's static libraries for Xcode.
xcrun --sdk iphoneos libtool -static -o app/Madeira/libdxmt_combined.a \
    build/dxmt-ios/libdxmt_unix.a toolchains/llvm-ios-build/lib/libLLVM*.a
bash build/rppairing-ios/build.sh
bash build/madeira-d3d12/build-pe.sh
bash build/madeira-dock/build.sh --check
bash build/wine-i386/build.sh
mkdir -p wine/build-aarch64
if [ ! -f wine/build-aarch64/config.status ]; then
    (cd wine/build-aarch64 && ../configure --enable-archs=aarch64 --without-x --disable-tests)
fi
for module in ntdll wow64 wow64win; do
    make -C "wine/build-aarch64/dlls/$module" -j"$JOBS"
    aarch64-w64-mingw32-strip --strip-debug \
        -o "app/Madeira/aarch64-windows/$module.dll" \
        "wine/build-aarch64/dlls/$module/aarch64-windows/$module.dll"
done
bash build/fex-wow64/build.sh
bash build/stage-licenses.sh
xcodebuild -project app/Madeira.xcodeproj -scheme Madeira -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath build/xcode-derived \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
    DEVELOPMENT_TEAM= build
bash tools/ci-package.sh
