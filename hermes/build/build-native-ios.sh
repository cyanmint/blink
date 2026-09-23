#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_ROOT=${BUILD_ROOT:-/root/hermes-build/native-ios}
SDK_VERSION=${IOS_SDK_VERSION:-16.5}
DEPLOYMENT_TARGET=${IPHONEOS_DEPLOYMENT_TARGET:-13.0}
SDK_REPO=${IOS_SDK_REPOSITORY:-https://github.com/theos/sdks.git}
HOST_OS=$(uname -s)
if [ -n "${IOS_SDK_ROOT:-}" ]; then
  SDK_ROOT=$IOS_SDK_ROOT
elif [ "$HOST_OS" = Darwin ]; then
  SDK_ROOT=$(xcrun --sdk iphoneos --show-sdk-path)
else
  SDK_ROOT=$BUILD_ROOT/sdks/iPhoneOS${SDK_VERSION}.sdk
fi
if [ -z "${HOST_PYTHON:-}" ] && [ "$HOST_OS" = Darwin ]; then
  HOST_PYTHON=$(command -v python3.13 || command -v python3 || true)
fi
HOST_PYTHON=${HOST_PYTHON:-$BUILD_ROOT/host-python/bin/python3.13}
export HOST_PYTHON
CPYTHON_REF=${CPYTHON_REF:-v3.13.9}
CPYTHON_ROOT=${CPYTHON_ROOT:-$BUILD_ROOT/cpython}
OPENSSL_REF=${OPENSSL_REF:-openssl-3.3.2}
OPENSSL_ROOT=${OPENSSL_ROOT:-$BUILD_ROOT/openssl}
OPENSSL_INSTALL=${OPENSSL_INSTALL:-$BUILD_ROOT/openssl-install}
TARGET_ROOT=${TARGET_ROOT:-$BUILD_ROOT/target}
TOOLBIN=$BUILD_ROOT/bin

mkdir -p "$BUILD_ROOT" "$TOOLBIN"

if [ "$HOST_OS" != Darwin ] && [ ! -d "$SDK_ROOT" ]; then
  SDK_REPO_DIR=$BUILD_ROOT/sdks
  if [ ! -d "$SDK_REPO_DIR/.git" ]; then
    git clone --filter=blob:none --sparse --depth=1 "$SDK_REPO" "$SDK_REPO_DIR"
    git -C "$SDK_REPO_DIR" sparse-checkout set "iPhoneOS${SDK_VERSION}.sdk"
  fi
fi
[ -d "$SDK_ROOT/usr/include" ] || { echo "missing iOS SDK: $SDK_ROOT" >&2; exit 3; }

if [ ! -d "$CPYTHON_ROOT/.git" ]; then
  git clone --filter=blob:none --depth=1 --branch "$CPYTHON_REF" https://github.com/python/cpython.git "$CPYTHON_ROOT"
fi

if [ ! -x "$HOST_PYTHON" ]; then
  HOST_ROOT=$BUILD_ROOT/host-cpython
  if [ ! -d "$HOST_ROOT/.git" ]; then
    git clone --filter=blob:none --depth=1 --branch "$CPYTHON_REF" https://github.com/python/cpython.git "$HOST_ROOT"
    (cd "$HOST_ROOT" && env -u SDKROOT -u CC -u CFLAGS -u CPPFLAGS -u LDFLAGS \
      ./configure --prefix="$BUILD_ROOT/host-python" --without-ensurepip --disable-test-modules)
    (cd "$HOST_ROOT" && env -u SDKROOT -u CC -u CFLAGS -u CPPFLAGS -u LDFLAGS make -j"${JOBS:-16}")
    (cd "$HOST_ROOT" && env -u SDKROOT -u CC -u CFLAGS -u CPPFLAGS -u LDFLAGS make install)
  fi
fi
"$HOST_PYTHON" --version

if [ "$HOST_OS" = Darwin ]; then
  LINKER_FLAGS=""
  # Xcode ships Apple's cctools ar/ranlib for SDK builds.  Recent Xcode
  # versions do not expose llvm-ar/llvm-ranlib through the default toolchain.
  LLVM_AR=$(xcrun --sdk iphoneos --find ar)
  LLVM_RANLIB=$(xcrun --sdk iphoneos --find ranlib)
else
  LINKER_FLAGS="-fuse-ld=lld"
  LLVM_AR=llvm-ar
  LLVM_RANLIB=llvm-ranlib
fi
cat > "$TOOLBIN/arm64-apple-ios-clang" <<EOF
#!/bin/sh
exec clang --target=arm64-apple-ios${DEPLOYMENT_TARGET} -isysroot "$SDK_ROOT" "\$@" $LINKER_FLAGS
EOF
cat > "$TOOLBIN/arm64-apple-ios-clang++" <<EOF
#!/bin/sh
exec clang++ --target=arm64-apple-ios${DEPLOYMENT_TARGET} -isysroot "$SDK_ROOT" "\$@" $LINKER_FLAGS
EOF
cat > "$TOOLBIN/arm64-apple-ios-cpp" <<EOF
#!/bin/sh
exec clang -E --target=arm64-apple-ios${DEPLOYMENT_TARGET} -isysroot "$SDK_ROOT" "\$@"
EOF
cat > "$TOOLBIN/arm64-apple-ios-ar" <<'EOF'
#!/bin/sh
exec __LLVM_AR__ "$@"
EOF
cat > "$TOOLBIN/arm64-apple-ios-ranlib" <<'EOF'
#!/bin/sh
exec __LLVM_RANLIB__ "$@"
EOF
sed -i.bak "s#__LLVM_AR__#$LLVM_AR#; s#__LLVM_RANLIB__#$LLVM_RANLIB#" \
  "$TOOLBIN/arm64-apple-ios-ar" "$TOOLBIN/arm64-apple-ios-ranlib"
chmod +x "$TOOLBIN"/*

if [ ! -d "$OPENSSL_ROOT/.git" ]; then
  git clone --depth=1 --branch "$OPENSSL_REF" https://github.com/openssl/openssl.git "$OPENSSL_ROOT"
fi
if [ ! -f "$OPENSSL_INSTALL/lib/libssl.a" ] || [ ! -f "$OPENSSL_INSTALL/lib/libcrypto.a" ]; then
  (
    cd "$OPENSSL_ROOT"
    make clean >/dev/null 2>&1 || true
    CC="$TOOLBIN/arm64-apple-ios-clang" \
      AR="$TOOLBIN/arm64-apple-ios-ar" \
      RANLIB="$TOOLBIN/arm64-apple-ios-ranlib" \
      CFLAGS="-I$SDK_ROOT/usr/include -isysroot $SDK_ROOT -miphoneos-version-min=$DEPLOYMENT_TARGET" \
      ./Configure iphoneos-cross no-shared no-apps no-tests \
        --prefix="$OPENSSL_INSTALL" -static
    if [ "$HOST_OS" != Darwin ]; then
      sed -i.bak "s#/SDKs/#$SDK_ROOT#g" Makefile
    fi
    make -j16 build_libs
    make install_sw
  )
fi

TARGET_ROOT=$BUILD_ROOT/target-cpython
TARGET_STAMP="$TARGET_ROOT/.hermes-cpython-ref"
if [ ! -f "$TARGET_STAMP" ] || [ "$(cat "$TARGET_STAMP")" != "$CPYTHON_REF" ]; then
  rm -rf "$TARGET_ROOT"
  mkdir -p "$TARGET_ROOT"
  git -C "$CPYTHON_ROOT" archive HEAD | tar -x -C "$TARGET_ROOT"
  printf '%s\n' "$CPYTHON_REF" > "$TARGET_STAMP"
else
  echo "Reusing cached CPython target objects for $CPYTHON_REF"
fi
BUILD_TRIPLE=$(cd "$TARGET_ROOT" && ./config.guess)
cat > "$TARGET_ROOT/ios_compat.c" <<'EOF'
#include <stdint.h>
int __isPlatformVersionAtLeast(uint32_t platform, uint32_t major, uint32_t minor, uint32_t subminor) {
    (void)platform; (void)major; (void)minor; (void)subminor;
    return 1;
}
EOF
clang --target=arm64-apple-ios${DEPLOYMENT_TARGET} -isysroot "$SDK_ROOT" \
  -c "$TARGET_ROOT/ios_compat.c" -o "$TARGET_ROOT/ios_compat.o"
(cd "$TARGET_ROOT" && \
  PATH="$TOOLBIN:/usr/bin:/bin" CC=arm64-apple-ios-clang AR=arm64-apple-ios-ar RANLIB=arm64-apple-ios-ranlib \
    CPPFLAGS="-DOPENSSL_THREADS -I$OPENSSL_INSTALL/include" \
    LDFLAGS="-L$OPENSSL_INSTALL/lib" \
    LIBS="$TARGET_ROOT/ios_compat.o -lssl -lcrypto" \
    py_cv_module__lzma=n/a py_cv_module__bz2=n/a py_cv_module__dbm=n/a \
    py_cv_module__gdbm=n/a py_cv_module_readline=n/a py_cv_module__curses=n/a \
    py_cv_module__curses_panel=n/a py_cv_module__blake2=n/a py_cv_module__ctypes=n/a \
    py_cv_module__decimal=n/a \
    py_cv_module__elementtree=n/a py_cv_module__uuid=n/a \
    ./configure --host=arm64-apple-ios${DEPLOYMENT_TARGET} \
    --build="$BUILD_TRIPLE" --with-build-python="$HOST_PYTHON" \
    --without-ensurepip --disable-test-modules --disable-ipv6 --with-lto=no \
    --enable-framework)
python3 - "$TARGET_ROOT/Makefile" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("Python.framework/Python", ""), encoding="utf-8", newline="\n")
PY
python3 - "$TARGET_ROOT/Modules/Setup.stdlib" "$TARGET_ROOT/Modules/Setup.local" "$TARGET_ROOT/Makefile" <<'PY'
import pathlib, sys
source, target, makefile = sys.argv[1:]
lines = pathlib.Path(source).read_text().splitlines()
for i, line in enumerate(lines):
    if line.strip() == "*shared*": lines[i] = "*static*"
    if line.startswith("_decimal "): lines[i] += " -IModules/_decimal/libmpdec Modules/_decimal/libmpdec/libmpdec.a"
pathlib.Path(target).write_text("\n".join(lines) + "\n")
objects = []
for line in lines:
    line = line.strip()
    if not line or line.startswith("#") or line.startswith("*"):
        continue
    for token in line.split()[1:]:
        if token.endswith(".c"):
            source_path = token.removeprefix("$(srcdir)/") if token.startswith("$(srcdir)/") else token
            objects.append("Modules/" + source_path[:-2] + ".o")
objects = sorted(set(objects))
pathlib.Path(pathlib.Path(makefile).parent / "native-module-objects.txt").write_text("\n".join(objects) + "\n")
PY
python3 - "$TARGET_ROOT/Modules/Setup.local" "$BUILD_ROOT/native_modules.c" <<'PY'
import re
import sys
from pathlib import Path

setup, output = map(Path, sys.argv[1:])
modules = []
for line in setup.read_text(encoding="utf-8").splitlines():
    line = line.split("#", 1)[0].strip()
    if not line or line.startswith("*"):
        continue
    name = line.split()[0]
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
        modules.append(name)
modules = sorted(set(modules))
with output.open("w", encoding="utf-8", newline="\n") as stream:
    stream.write("#include <Python.h>\n")
    for name in modules:
        stream.write(f"PyMODINIT_FUNC PyInit_{name}(void);\n")
    stream.write("\nint hermes_register_native_modules(void) {\n")
    for name in modules:
        stream.write(f'    PyImport_AppendInittab("{name}", PyInit_{name});\n')
    stream.write("    return 0;\n}\n")
PY

(cd "$TARGET_ROOT" && \
  PATH="$TOOLBIN:/usr/bin:/bin" make -n -o Makefile libpython3.13.a > native-libpython-dryrun.txt)
python3 - "$TARGET_ROOT/native-libpython-dryrun.txt" "$TARGET_ROOT/native-module-objects.txt" <<'PY'
from pathlib import Path
import shlex, sys
import re
dryrun, output = map(Path, sys.argv[1:])
objects = set()
for line in dryrun.read_text(encoding="utf-8", errors="replace").splitlines():
    # GNU ar and Apple's ar spell the archive operation differently. Only
    # key on the output archive, not on one platform's flags.
    if "libpython3.13.a" not in line:
        continue
    tokens = shlex.split(line)
    try:
        index = tokens.index("libpython3.13.a")
    except ValueError:
        continue
    objects.update(token for token in tokens[index + 1:] if token.endswith(".o"))
makefile = dryrun.parent / "Makefile"
make_lines = makefile.read_text(encoding="utf-8", errors="replace").splitlines()
for index, line in enumerate(make_lines):
    if not re.match(r"^\s*MODOBJS\s*=", line):
        continue
    value = line.split("=", 1)[1]
    cursor = index + 1
    while value.rstrip().endswith("\\") and cursor < len(make_lines):
        value = value.rstrip()[:-1] + " " + make_lines[cursor]
        cursor += 1
    objects.update(token for token in value.split() if token.endswith(".o"))
if not objects:
    raise SystemExit("could not extract libpython object list from Makefile dry-run")
output.write_text("\n".join(sorted(objects)) + "\n", encoding="utf-8", newline="\n")
PY
(cd "$TARGET_ROOT" && \
  PATH="$TOOLBIN:/usr/bin:/bin" make -o Makefile -o Modules/config.c -o Modules/config.h -j"${JOBS:-16}" \
    $(cat native-module-objects.txt) Modules/binascii.o Modules/_struct.o Modules/socketmodule.o Modules/selectmodule.o Modules/mathmodule.o Modules/cmathmodule.o Modules/_contextvarsmodule.o Modules/arraymodule.o Modules/_randommodule.o)
(cd "$TARGET_ROOT" && \
  PATH="$TOOLBIN:/usr/bin:/bin" make -o Makefile -j"${JOBS:-16}" \
    Modules/_hacl/libHacl_Hash_SHA2.a Modules/expat/libexpat.a)
(cd "$TARGET_ROOT" && \
  find Modules -type f -name '*.o' -print >> native-module-objects.txt && \
  sort -u native-module-objects.txt | \
  grep -v '^Modules/_hacl/Hacl_Hash_SHA2\.o$' | \
  grep -v '^Modules/expat/' > native-module-objects.filtered && \
  printf '%s\n' Modules/binascii.o >> native-module-objects.filtered && \
  printf '%s\n' Modules/selectmodule.o >> native-module-objects.filtered && \
  printf '%s\n' Modules/_contextvarsmodule.o >> native-module-objects.filtered && \
  printf '%s\n' Modules/arraymodule.o >> native-module-objects.filtered && \
  printf '%s\n' Modules/_randommodule.o >> native-module-objects.filtered && \
  sort -u native-module-objects.filtered > native-module-objects.txt)
(cd "$TARGET_ROOT" && python3 - "$TARGET_ROOT/Modules/Setup.local" native-module-objects.txt "$BUILD_ROOT/native_modules.c" <<'PY'
import re
import sys
from pathlib import Path

setup, objects_file, output = map(Path, sys.argv[1:])
objects = set(objects_file.read_text(encoding="utf-8").splitlines())
modules = []
for raw in setup.read_text(encoding="utf-8").splitlines():
    line = raw.split("#", 1)[0].strip()
    if not line or line.startswith("*"):
        continue
    fields = line.split()
    name = fields[0]
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
        continue
    source_objects = []
    for token in fields[1:]:
        if token.endswith(".c"):
            source = token.removeprefix("$(srcdir)/") if token.startswith("$(srcdir)/") else token
            source = source.removeprefix("./")
            object_path = source[:-2] + ".o"
            source_objects.append(object_path if object_path.startswith("Modules/") else "Modules/" + object_path)
    if any(source in objects for source in source_objects):
        modules.append(name)
modules = sorted(set(modules))
with output.open("w", encoding="utf-8", newline="\n") as stream:
    stream.write("#include <Python.h>\n")
    for name in modules:
        stream.write(f"PyMODINIT_FUNC PyInit_{name}(void);\n")
    stream.write("\nint hermes_register_native_modules(void) {\n")
    for name in modules:
        stream.write(f'    PyImport_AppendInittab("{name}", PyInit_{name});\n')
    stream.write("    return 0;\n}\n")
PY
)
(cd "$TARGET_ROOT" && \
  "$TOOLBIN/arm64-apple-ios-clang" -I"$TARGET_ROOT" -I"$TARGET_ROOT/Include" \
    -c "$BUILD_ROOT/native_modules.c" -o native_modules.o && \
  printf '%s\n' native_modules.o >> native-module-objects.txt && \
  sort -u native-module-objects.txt -o native-module-objects.txt)
(cd "$TARGET_ROOT" && \
  "$LLVM_AR" rcs libpython3.13.a $(cat native-module-objects.txt) && \
  "$LLVM_RANLIB" libpython3.13.a)

mkdir -p "$BUILD_ROOT/artifact"
CC=arm64-apple-ios-clang PATH="$TOOLBIN:$PATH" \
  HERMES_SKIP_RUNTIME_PACKAGE="${HERMES_SKIP_RUNTIME_PACKAGE:-0}" \
  bash "$ROOT/build/package-native-ios.sh" \
  "$TARGET_ROOT" "$BUILD_ROOT/artifact"
if [ "${HERMES_SKIP_RUNTIME_PACKAGE:-0}" != "1" ]; then
  rm -f "$ROOT/hermes"
  cp "$BUILD_ROOT/hermesrt.zip" "$ROOT/hermesrt.zip"
fi
if [ "${HERMES_RUNTIME_PYTHON_ONLY:-0}" != "1" ]; then
  mkdir -p "$ROOT/Frameworks"
  rm -rf "$ROOT/Frameworks/HermesRuntime.framework"
  cp -a "$BUILD_ROOT/artifact/HermesRuntime.framework" "$ROOT/Frameworks/HermesRuntime.framework"
  file "$ROOT/Frameworks/HermesRuntime.framework/HermesRuntime" "$ROOT/hermesrt.zip"
else
  file "$ROOT/hermesrt.zip"
fi
