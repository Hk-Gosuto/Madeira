#!/bin/bash
# Full Debug iPhone build, including the optional 32-bit guest runtime.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
cd "$R"
export PATH="$R/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin:$(brew --prefix bison)/bin:$(brew --prefix llvm)/bin:$PATH"
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-3}"
export JOBS="$CMAKE_BUILD_PARALLEL_LEVEL"
trap 'find build -type f \( -name "*.err" -o -name "err-*.txt" -o -name "*.log" \) -size +0c -exec tail -n 30 {} \;' ERR

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
make -C wine/build-macos -j"$JOBS" include/all
bash build/wine-pe/build-ntdll.sh
make -C wine/build-arm64ec -j"$JOBS" include/all
bash build/wine-pe/build-modules.sh
bash build/wine-pe/build-modules.sh dcomp ktmw32
bash build/ntdll-unix/build.sh
bash build/wineserver/build.sh
bash build/win32u-unix/build.sh

bash tools/ci-dxmt-pe.sh
bash build/dxmt-ios/build.sh
# The upstream incremental script does not create the combined archive on a
# clean checkout. Merge its objects with LLVM's static libraries for Xcode.
xcrun --sdk iphoneos libtool -static -o app/Madeira/libdxmt_combined.a \
    build/dxmt-ios/libdxmt_unix.a toolchains/llvm-ios-build/lib/libLLVM*.a
cargo test --manifest-path build/rppairing-ios/Cargo.toml --locked
bash build/rppairing-ios/build.sh
OUT="$R/app/Madeira/arm64ec-windows" bash build/madeira-d3d12/build-pe.sh
HOST_CC="$(xcrun --sdk macosx --find clang)" SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" \
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
