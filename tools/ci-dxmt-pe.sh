#!/bin/bash
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
TC="$R/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin"
WINE_BUILD="$R/wine/build-arm64ec"
export PATH="$TC:$(brew --prefix bison)/bin:$PATH"
# DXMT consumes Wine's import libraries, not just the committed runtime DLLs.
make -C "$WINE_BUILD" -j"${JOBS:-3}" \
    dlls/ntdll/arm64ec-windows/libntdll.a \
    dlls/dbghelp/arm64ec-windows/libdbghelp.a
cat > "$WINE_BUILD/dxmt-cross-arm64ec.txt" <<EOF
[binaries]
c = '$TC/arm64ec-w64-mingw32-clang'
cpp = '$TC/arm64ec-w64-mingw32-clang++'
ar = '$TC/arm64ec-w64-mingw32-ar'
strip = '$TC/arm64ec-w64-mingw32-strip'
windres = '$TC/arm64ec-w64-mingw32-windres'
dlltool = '$TC/arm64ec-w64-mingw32-dlltool'
[properties]
needs_exe_wrapper = true
[host_machine]
system = 'windows'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
cd "$R/dxmt"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
if [ ! -f build-arm64ec/build.ninja ]; then
    meson setup build-arm64ec --cross-file "$WINE_BUILD/dxmt-cross-arm64ec.txt" \
        --native-file build-osx.txt --buildtype release \
        -Dwine_build_path="$WINE_BUILD" -Dwine_builtin_dll=true
fi
meson compile -C build-arm64ec -j "${JOBS:-3}"
for module in winemetal/winemetal.dll d3d11/d3d11.dll dxgi/dxgi.dll d3d10/d3d10core.dll; do
    "$TC/arm64ec-w64-mingw32-strip" --strip-debug \
        -o "$R/app/Madeira/arm64ec-windows/$(basename "$module")" "build-arm64ec/src/$module"
done
