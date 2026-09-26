#!/usr/bin/env bash
# HermesLink AI-generated glue code; created by cyanmint's coding agent.
# AI-generated content has no copyright holder and is not subject to copyright.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TARGET_ROOT=${1:?target CPython build directory}
OUTPUT_FRAMEWORK=${2:?output framework directory}
BUILD_ROOT=$(dirname "$OUTPUT_FRAMEWORK")
HOST_PYTHON=${HOST_PYTHON:-$(dirname "$TARGET_ROOT")/host-python/bin/python3.13}
ARCHIVE="$BUILD_ROOT/hermesrt.zip"
OPENSSL_INSTALL=${OPENSSL_INSTALL:-$BUILD_ROOT/openssl-install}

[ -f "$TARGET_ROOT/libpython3.13.a" ] || { echo "missing target libpython3.13.a" >&2; exit 2; }
[ -d "$TARGET_ROOT/Lib/encodings" ] || { echo "missing CPython standard library" >&2; exit 2; }

if [ "${HERMES_BUILD_RUNTIME_ZIP:-1}" = "1" ]; then
  CPYTHON_ROOT=${CPYTHON_ROOT:-$(dirname "$TARGET_ROOT")/cpython}
  BUILD_ROOT="$BUILD_ROOT" HOST_PYTHON="$HOST_PYTHON" \
    HERMES_VENDOR=${HERMES_VENDOR:-$BUILD_ROOT/vendor} \
    bash "$ROOT/build/build-hermesrt-zip.sh" "$CPYTHON_ROOT" "$ARCHIVE"
fi

FRAMEWORK="$OUTPUT_FRAMEWORK/HermesRuntime.framework"
mkdir -p "$FRAMEWORK/Headers" "$FRAMEWORK/Modules"

CC=${CC:-arm64-apple-ios-clang}
"$CC" -I"$TARGET_ROOT" -I"$TARGET_ROOT/Include" -I"$TARGET_ROOT" -I"$ROOT/../Blink" \
  -c "$ROOT/overlay/cpython/Programs/hermes_main.c" -o "$BUILD_ROOT/hermes_main.o"
"$CC" -mios-version-min="${IPHONEOS_DEPLOYMENT_TARGET:-13.0}" \
-Wl,-headerpad_max_install_names -Wl,-x -Wl,-no_function_starts -Wl,-no_data_in_code_info -Wl,-all_load "$TARGET_ROOT/libpython3.13.a" -Wl,-force_load,"$TARGET_ROOT/Modules/_hacl/libHacl_Hash_SHA2.a" -Wl,-force_load,"$TARGET_ROOT/Modules/expat/libexpat.a" "$BUILD_ROOT/hermes_main.o" \
  -Wl,-rpath,@loader_path -framework CoreFoundation -ldl -lpthread -lm -lz -lsqlite3 \
  -L"$OPENSSL_INSTALL/lib" -lssl -lcrypto "$TARGET_ROOT/ios_compat.o" \
  -dynamiclib -install_name "@rpath/HermesRuntime.framework/HermesRuntime" \
  -Wl,-exported_symbol,_hermes_runtime_main \
  -o "$FRAMEWORK/HermesRuntime"
chmod 755 "$FRAMEWORK/HermesRuntime"
cat > "$FRAMEWORK/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>HermesRuntime</string>
<key>CFBundleIdentifier</key><string>com.cyan.hermesruntime</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
cat > "$FRAMEWORK/Headers/HermesRuntime.h" <<'HEADER'
#ifndef HERMES_RUNTIME_H
#define HERMES_RUNTIME_H
int hermes_runtime_main(int argc, char **argv);
#endif
HEADER
cat > "$FRAMEWORK/Modules/module.modulemap" <<'MODULEMAP'
framework module HermesRuntime {
  umbrella header "HermesRuntime.h"
  export *
}
MODULEMAP
if [ "${HERMES_BUILD_RUNTIME_ZIP:-1}" = "1" ]; then
  "$HOST_PYTHON" "$ROOT/build/validate-runtime-zip.py" "$ARCHIVE"
  cp "$ARCHIVE" "$ROOT/hermesrt.zip"
fi
