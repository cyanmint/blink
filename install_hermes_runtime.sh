#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BLINK_ROOT=${BLINK_ROOT:-$ROOT}
INPUT_ROOT=${1:-${NATIVE_IOS_BUILD_ROOT:-$ROOT/hermes}}
SOURCE_FRAMEWORK=${HERMES_RUNTIME_FRAMEWORK:-$INPUT_ROOT/HermesRuntime.framework}
SOURCE_RUNTIME=${HERMES_RUNTIME_ARCHIVE:-$INPUT_ROOT/hermesrt.zip}
DEST_ROOT="$BLINK_ROOT/Resources"
DEST_FRAMEWORK="$BLINK_ROOT/Frameworks/HermesRuntime.framework"
DEST_RUNTIME="$DEST_ROOT/hermesrt.zip"

[ -f "$SOURCE_FRAMEWORK/HermesRuntime" ] || { echo "missing Hermes runtime framework: $SOURCE_FRAMEWORK" >&2; exit 2; }
[ -f "$SOURCE_RUNTIME" ] || { echo "missing Hermes runtime archive: $SOURCE_RUNTIME" >&2; exit 2; }
command -v unzip >/dev/null 2>&1 || { echo "unzip is required" >&2; exit 2; }
unzip -t "$SOURCE_RUNTIME" >/dev/null

python3 - "$SOURCE_RUNTIME" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    names = archive.namelist()
    if len(names) != len(set(names)):
        raise SystemExit("duplicate ZIP paths")
    if any(part == ".git" for name in names for part in name.split("/")):
        raise SystemExit("runtime archive contains .git")
    required = {
        "hermes/hermes_cli/main.py",
        "hermes-webui/api/config.py",
        "python/encodings/__init__.py",
    }
    missing = sorted(required - set(names))
    if missing:
        raise SystemExit("runtime archive missing: " + ", ".join(missing))
PY

mkdir -p "$DEST_ROOT"
rm -f "$DEST_ROOT/hermes"
rm -rf "$DEST_FRAMEWORK.tmp"
cp -a "$SOURCE_FRAMEWORK" "$DEST_FRAMEWORK.tmp"
install -m 644 "$SOURCE_RUNTIME" "$DEST_RUNTIME.tmp"
rm -rf "$DEST_FRAMEWORK"
mv "$DEST_FRAMEWORK.tmp" "$DEST_FRAMEWORK"
mv -f "$DEST_RUNTIME.tmp" "$DEST_RUNTIME"
chmod 755 "$DEST_FRAMEWORK/HermesRuntime"
printf 'Installed %s (%s bytes)\n' "$DEST_FRAMEWORK" "$(wc -c < "$DEST_FRAMEWORK/HermesRuntime")"
printf 'Installed %s (%s bytes)\n' "$DEST_RUNTIME" "$(wc -c < "$DEST_RUNTIME")"
