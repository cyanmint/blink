#!/usr/bin/env bash
# HermesLink AI-generated glue code; created by cyanmint's coding agent.
# AI-generated content has no copyright holder and is not subject to copyright.
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
PYTHON_VERSION=${PYTHON_VERSION:-3.13}
PYTHON_LIBRARY="libpython${PYTHON_VERSION}.a"
HOST_PYTHON=${HOST_PYTHON:-$BUILD_ROOT/host-python/bin/python${PYTHON_VERSION}}
export HOST_PYTHON
ASHELL_ROOT=${ASHELL_ROOT:-$BUILD_ROOT/a-shell}
CPYTHON_ROOT=${CPYTHON_ROOT:-$ASHELL_ROOT/cpython}
CPYTHON_REF=${CPYTHON_REF:-0c3aa6418f2f8d874e1be62e45226af002bbcc8d}
OPENSSL_REF=${OPENSSL_REF:-openssl-3.3.2}
OPENSSL_ROOT=${OPENSSL_ROOT:-$BUILD_ROOT/openssl}
OPENSSL_INSTALL=${OPENSSL_INSTALL:-$BUILD_ROOT/openssl-install}
LIBFFI_ROOT=${LIBFFI_ROOT:-$BUILD_ROOT/libffi}
LIBFFI_INSTALL=${LIBFFI_INSTALL:-$BUILD_ROOT/libffi-install}
TARGET_ROOT=${TARGET_ROOT:-$BUILD_ROOT/target}
TOOLBIN=$BUILD_ROOT/bin
IOS_SYSTEM_FRAMEWORK=${IOS_SYSTEM_FRAMEWORK:-$ROOT/../xcfs/.build/artifacts/xcfs/ios_system/ios_system.xcframework/ios-arm64/ios_system.framework}
IOS_SYSTEM_FRAMEWORK_DIR=$(dirname "$IOS_SYSTEM_FRAMEWORK")
export IOS_SYSTEM_FRAMEWORK

mkdir -p "$BUILD_ROOT" "$TOOLBIN"

if [ "$HOST_OS" != Darwin ] && [ ! -d "$SDK_ROOT" ]; then
  SDK_REPO_DIR=$BUILD_ROOT/sdks
  if [ ! -d "$SDK_REPO_DIR/.git" ]; then
    git clone --filter=blob:none --sparse --depth=1 "$SDK_REPO" "$SDK_REPO_DIR"
    git -C "$SDK_REPO_DIR" sparse-checkout set "iPhoneOS${SDK_VERSION}.sdk"
  fi
fi
[ -d "$SDK_ROOT/usr/include" ] || { echo "missing iOS SDK: $SDK_ROOT" >&2; exit 3; }
[ -f "$IOS_SYSTEM_FRAMEWORK/ios_system" ] || {
  echo "missing a-Shell ios_system framework: $IOS_SYSTEM_FRAMEWORK" >&2
  echo "Run get_frameworks.sh first or set IOS_SYSTEM_FRAMEWORK" >&2
  exit 3
}

if [ ! -d "$CPYTHON_ROOT/.git" ]; then
  bash "$ROOT/build/fetch-ashell.sh" "$ASHELL_ROOT"
fi

if [ ! -x "$HOST_PYTHON" ]; then
  HOST_ROOT=$BUILD_ROOT/host-cpython
  if [ ! -f "$HOST_ROOT/configure" ]; then
    rm -rf "$HOST_ROOT"
    mkdir -p "$HOST_ROOT"
    git -C "$CPYTHON_ROOT" archive HEAD | tar -x -C "$HOST_ROOT"
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

if [ ! -f "$LIBFFI_ROOT/configure" ]; then
  rm -rf "$LIBFFI_ROOT"
  mkdir -p "$LIBFFI_ROOT"
  curl -fsSL https://github.com/libffi/libffi/releases/download/v3.4.6/libffi-3.4.6.tar.gz \
    | tar -xz --strip-components=1 -C "$LIBFFI_ROOT"
fi
if [ ! -f "$LIBFFI_INSTALL/lib/libffi.a" ] || [ ! -f "$LIBFFI_INSTALL/include/ffi.h" ]; then
  (
    cd "$LIBFFI_ROOT"
    make distclean >/dev/null 2>&1 || true
    CC="$TOOLBIN/arm64-apple-ios-clang" \
      AR="$TOOLBIN/arm64-apple-ios-ar" \
      RANLIB="$TOOLBIN/arm64-apple-ios-ranlib" \
      CFLAGS="-isysroot $SDK_ROOT -miphoneos-version-min=$DEPLOYMENT_TARGET" \
      ./configure --host=aarch64-apple-darwin --enable-static --disable-shared \
        --disable-builddir --prefix="$LIBFFI_INSTALL"
    python3 - "$LIBFFI_ROOT/src/aarch64/sysv.S" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text()
text = ''.join(line for line in text.splitlines(keepends=True)
               if 'cfi_def_cfa' not in line and 'cfi_adjust_cfa_offset' not in line)
path.write_text(text)
PY
    make -j"${JOBS:-16}"
    make install
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
cat > "$TARGET_ROOT/ios_ctypes_compat.h" <<'EOF'
#ifndef HERMES_IOS_CTYPES_COMPAT_H
#define HERMES_IOS_CTYPES_COMPAT_H
extern char *ios_getenv(const char *name);
#endif
EOF
python3 - "$TARGET_ROOT/Modules/_ctypes/_ctypes.c" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
include = '#include "ios_ctypes_compat.h"\n'
if include not in text:
    path.write_text(include + text, encoding="utf-8", newline="\n")
PY
BUILD_TRIPLE=$(cd "$TARGET_ROOT" && ./config.guess)
cat > "$TARGET_ROOT/ios_compat.c" <<'EOF'
#include <stdint.h>
#include <sys/types.h>
#include <sys/wait.h>

/* CPython's iOS port aliases waitpid to this entry point.  ios_system
 * exports the command/session APIs, but not this CPython compatibility symbol;
 * keep the shim limited to the POSIX wait operation and leave all other
 * a-Shell APIs to the linked framework/host. */
__attribute__((weak))
pid_t ios_full_waitpid(pid_t pid, int *status, int options) {
    return waitpid(pid, status, options);
}

/* CPython's iOS headers import the complete ios_system ABI from the host
 * application.  Do not provide local stream/process fallbacks here: doing so
 * hides a missing a-Shell dependency and can bind CPython to NULL TLS streams.
 * This SDK compatibility symbol is unrelated to ios_system and is retained
 * only for SDKs which do not export it. */
__attribute__((weak))
int __isPlatformVersionAtLeast(uint32_t platform, uint32_t major,
                               uint32_t minor, uint32_t subminor) {
    (void)platform; (void)major; (void)minor; (void)subminor;
    return 1;
}
EOF
clang --target=arm64-apple-ios${DEPLOYMENT_TARGET} -isysroot "$SDK_ROOT" \
  -c "$TARGET_ROOT/ios_compat.c" -o "$TARGET_ROOT/ios_compat.o"
(cd "$TARGET_ROOT" && \
  PATH="$TOOLBIN:/usr/bin:/bin" CC=arm64-apple-ios-clang AR=arm64-apple-ios-ar RANLIB=arm64-apple-ios-ranlib \
    CPPFLAGS="-DOPENSSL_THREADS -I$OPENSSL_INSTALL/include -I$LIBFFI_INSTALL/include -I$ROOT/../Blink" \
    LDFLAGS="-L$OPENSSL_INSTALL/lib -L$LIBFFI_INSTALL/lib -F$IOS_SYSTEM_FRAMEWORK_DIR -framework ios_system" \
    LIBS="$TARGET_ROOT/ios_compat.o -lssl -lcrypto -lffi -F$IOS_SYSTEM_FRAMEWORK_DIR -framework ios_system" \
    py_cv_module__lzma=n/a py_cv_module__bz2=n/a py_cv_module__dbm=n/a \
    py_cv_module__gdbm=n/a py_cv_module_readline=n/a py_cv_module__curses=n/a \
    py_cv_module__curses_panel=n/a py_cv_module__blake2=n/a \
    py_cv_module__decimal=n/a \
    py_cv_module__elementtree=n/a py_cv_module__uuid=n/a \
    ./configure --host=arm64-apple-ios${DEPLOYMENT_TARGET} \
    --build="$BUILD_TRIPLE" --with-build-python="$HOST_PYTHON" \
    --without-ensurepip --disable-test-modules --disable-ipv6 --with-lto=no \
    --enable-framework)
sed -i.bak "s#-lffi#-Wl,-force_load,$LIBFFI_INSTALL/lib/libffi.a#g" "$TARGET_ROOT/Makefile"
python3 - "$TARGET_ROOT/Makefile" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("Python.framework/Python", ""), encoding="utf-8", newline="\n")
PY
python3 - "$TARGET_ROOT/Modules/Setup_iOS.local" "$TARGET_ROOT/Modules/Setup.local" "$TARGET_ROOT/Makefile" <<'PY'
import pathlib, sys
source, target, makefile = sys.argv[1:]
lines = pathlib.Path(source).read_text().splitlines()
optional_unavailable = {"_decimal", "_bz2", "_lzma", "_dbm", "fcntl", "resource", "grp", "syslog", "termios"}
lines = [line for line in lines
         if not line.strip().startswith(tuple(name + " " for name in optional_unavailable))
         and not (line.strip() and not line.lstrip().startswith("#")
                  and (line.split()[0] == "xxsubtype"
                       or line.split()[0].startswith("_test")
                       or line.split()[0] == "_xxtestfuzz"))]
for i, line in enumerate(lines):
    if line.strip() == "*shared*": lines[i] = "*static*"

pathlib.Path(target).write_text("\n".join(lines) + "\n")
objects = []
for line in lines:
    line = line.strip()
    if not line or line.startswith("#") or line.startswith("*"):
        continue
    for token in line.split()[1:]:
        if token.endswith(".c"):
            source_path = token[len("$(srcdir)/"):] if token.startswith("$(srcdir)/") else token
            if source_path.startswith("Modules/"):
                source_path = source_path[len("Modules/"):]
            objects.append("Modules/" + source_path[:-2] + ".o")
objects = sorted(set(objects))
pathlib.Path(pathlib.Path(makefile).parent / "native-module-objects.txt").write_text("\n".join(objects) + "\n")
PY
(cd "$TARGET_ROOT" && \
  PATH="$TOOLBIN:/usr/bin:/bin" make -n -o Makefile "$PYTHON_LIBRARY" > native-libpython-dryrun.txt)
python3 - "$TARGET_ROOT/native-libpython-dryrun.txt" "$TARGET_ROOT/native-module-objects.txt" <<'PY'
from pathlib import Path
import shlex, sys
import re
dryrun, output = map(Path, sys.argv[1:])
objects = set(output.read_text(encoding="utf-8").splitlines()) if output.exists() else set()
for line in dryrun.read_text(encoding="utf-8", errors="replace").splitlines():
    if "$PYTHON_LIBRARY" not in line or " rcs " not in f" {line} ":
        continue
    tokens = shlex.split(line)
    try:
        index = tokens.index("$PYTHON_LIBRARY")
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
  PATH="$TOOLBIN:/usr/bin:/bin" CPPFLAGS="-IModules/_decimal/libmpdec" make -o Makefile -o Modules/config.c -o Modules/config.h -j"${JOBS:-16}" \
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
python3 - "$TARGET_ROOT/Modules/Setup.local" "$TARGET_ROOT/native-module-objects.txt" "$BUILD_ROOT/native_modules.c" "$TARGET_ROOT/native-module-manifest.txt" <<'PY'
import re
import sys
from pathlib import Path

setup, objects_file, output, manifest = map(Path, sys.argv[1:])
objects = set(objects_file.read_text(encoding="utf-8").splitlines())
optional_unavailable = {"_decimal", "_bz2", "_lzma", "_dbm", "fcntl", "resource", "grp", "syslog", "termios"}
module_specs = []
for line in setup.read_text(encoding="utf-8").splitlines():
    line = line.split("#", 1)[0].strip()
    if not line or line.startswith("*"):
        continue
    fields = line.split()
    name = fields[0]
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
        continue
    if name in optional_unavailable:
        continue
    # Setup_iOS.local also contains CPython's test extensions.  They are not
    # part of Hermes and pull in test-only dependencies; every production
    # extension, however, must be present in the final static archive.
    if name == "xxsubtype" or name.startswith("_test") or name == "_xxtestfuzz":
        continue
    source_objects = set()
    for token in fields[1:]:
        if not token.endswith(".c"):
            continue
        if token.startswith("$(srcdir)/"):
            source = token[len("$(srcdir)/"):]
        else:
            source = token
        # Setup.local uses both $(srcdir)/foo.c and foo.c forms.  The
        # previous token[2:-2] slicing produced a bogus "srcdir)/..."
        # path, so none of the statically built extension modules were
        # registered in the inittab (notably binascii).
        if source.startswith("Modules/"):
            source = source[len("Modules/"):]
        source_objects.add("Modules/" + source[:-2] + ".o")
    if source_objects:
        module_specs.append((name, source_objects))
missing = []
modules = []
for name, source_objects in module_specs:
    absent = sorted(source_objects - objects)
    if absent:
        missing.append(f"{name}: {', '.join(absent)}")
    else:
        modules.append(name)
if missing:
    raise SystemExit("configured static CPython modules were not built:\n" + "\n".join(missing))
modules = sorted(set(modules))
manifest.write_text("\n".join(modules) + "\n", encoding="utf-8", newline="\n")
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
  "$TOOLBIN/arm64-apple-ios-clang" -I"$TARGET_ROOT" -I"$TARGET_ROOT/Include" -I"$ROOT/../Blink" \
    -c "$BUILD_ROOT/native_modules.c" -o native_modules.o && \
  printf '%s\n' native_modules.o >> native-module-objects.txt && \
  sort -u native-module-objects.txt -o native-module-objects.txt)
(cd "$TARGET_ROOT" && \
  "$LLVM_AR" rcs "$PYTHON_LIBRARY" $(cat native-module-objects.txt) && \
  "$LLVM_RANLIB" "$PYTHON_LIBRARY")

mkdir -p "$BUILD_ROOT/artifact"
CC=arm64-apple-ios-clang PATH="$TOOLBIN:$PATH" \
  bash "$ROOT/build/package-native-ios.sh" \
  "$TARGET_ROOT" "$BUILD_ROOT/artifact"
rm -f "$ROOT/hermes"
mkdir -p "$ROOT/Frameworks"
rm -rf "$ROOT/Frameworks/HermesRuntime.framework"
cp -a "$BUILD_ROOT/artifact/HermesRuntime.framework" "$ROOT/Frameworks/HermesRuntime.framework"
cp "$BUILD_ROOT/hermesrt.zip" "$ROOT/hermesrt.zip"
file "$ROOT/Frameworks/HermesRuntime.framework/HermesRuntime" "$ROOT/hermesrt.zip"
