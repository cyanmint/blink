#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_ROOT=${BUILD_ROOT:-/root/hermes-build/python-runtime}
CPYTHON_REF=${CPYTHON_REF:-v3.13.9}
CPYTHON_ROOT=${CPYTHON_ROOT:-$BUILD_ROOT/cpython}
HOST_PYTHON=${HOST_PYTHON:-$(command -v python3)}

mkdir -p "$BUILD_ROOT"
if [ ! -d "$CPYTHON_ROOT/.git" ]; then
  git clone --filter=blob:none --depth=1 --branch "$CPYTHON_REF" \
    https://github.com/python/cpython.git "$CPYTHON_ROOT"
fi
[ -d "$CPYTHON_ROOT/Lib/encodings" ] || {
  echo "missing CPython standard library: $CPYTHON_ROOT/Lib" >&2
  exit 2
}
"$HOST_PYTHON" --version

mkdir -p "$BUILD_ROOT/artifact"
HERMES_RUNTIME_PYTHON_ONLY=1 \
HOST_PYTHON="$HOST_PYTHON" \
HERMES_REFRESH_VENDOR=1 \
bash "$ROOT/build/package-native-ios.sh" "$CPYTHON_ROOT" "$BUILD_ROOT/artifact"
cp "$BUILD_ROOT/hermesrt.zip" "$BUILD_ROOT/artifact/hermesrt.zip"
cp "$BUILD_ROOT/hermesrt.zip" "$ROOT/hermesrt.zip"

python3 - "$BUILD_ROOT/artifact/hermesrt.zip" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    names = set(archive.namelist())
    assert 'hermes-runtime.timestamp' in names
    assert archive.read('hermes-runtime.timestamp').strip().isdigit()
    assert 'python/encodings/__init__.py' in names
    assert 'hermes/hermes_cli/main.py' in names
    assert not any(name.endswith(('.so', '.dylib', '.pyd', '.wasm')) for name in names)
print('Python-only hermesrt.zip package passed')
PY
