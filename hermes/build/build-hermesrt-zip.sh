#!/usr/bin/env bash
# Build the pure-Python Hermes runtime archive without compiling a native runtime.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_ROOT=${BUILD_ROOT:-$ROOT/build/python-runtime}
CPYTHON_REF=${CPYTHON_REF:-v3.13.9}
CPYTHON_ROOT=${1:-${CPYTHON_ROOT:-$BUILD_ROOT/cpython}}
ARCHIVE=${2:-$ROOT/hermesrt.zip}
HOST_PYTHON=${HOST_PYTHON:-$(command -v python3.13 || command -v python3)}
HERMES_SOURCE=${HERMES_SOURCE:-$ROOT/build/external/hermes-agent}
WEBUI_SOURCE=${WEBUI_SOURCE:-$ROOT/build/external/hermes-webui}
VENDOR_ROOT=${HERMES_VENDOR:-$BUILD_ROOT/vendor}

mkdir -p "$BUILD_ROOT" "$(dirname "$ARCHIVE")"
if [ ! -d "$CPYTHON_ROOT/Lib/encodings" ]; then
  rm -rf "$CPYTHON_ROOT"
  git clone --filter=blob:none --depth=1 --branch "$CPYTHON_REF" \
    https://github.com/python/cpython.git "$CPYTHON_ROOT"
fi
[ -f "$CPYTHON_ROOT/Lib/encodings/__init__.py" ] || {
  echo "missing CPython standard library: $CPYTHON_ROOT/Lib" >&2
  exit 2
}
[ -x "$HOST_PYTHON" ] || { echo "missing host Python: $HOST_PYTHON" >&2; exit 2; }

if [ ! -f "$HERMES_SOURCE/hermes_cli/main.py" ] || [ ! -f "$WEBUI_SOURCE/api/config.py" ]; then
  bash "$ROOT/build/fetch-sources.sh"
fi
[ -f "$HERMES_SOURCE/hermes_cli/main.py" ] || { echo "missing Hermes Agent source" >&2; exit 2; }
[ -f "$WEBUI_SOURCE/api/config.py" ] || { echo "missing Hermes WebUI source" >&2; exit 2; }

mkdir -p "$(dirname "$VENDOR_ROOT")"
if [ "${HERMES_REFRESH_VENDOR:-1}" = "1" ]; then
  command -v uv >/dev/null 2>&1 || { echo "uv is required to vendor pure-Python dependencies" >&2; exit 2; }
  rm -rf "$VENDOR_ROOT"
  mkdir -p "$VENDOR_ROOT"
  uv pip install --only-binary :all: --target "$VENDOR_ROOT" --python "$HOST_PYTHON" \
    openai==1.3.8 pydantic==1.10.15 'httpx[socks]==0.28.1'
  uv pip install --only-binary :all: --target "$VENDOR_ROOT" --python "$HOST_PYTHON" --no-deps \
    certifi==2026.5.20 python-dotenv==1.2.2 fire==0.7.1 rich==14.3.3 \
    tenacity==9.1.4 pyyaml==6.0.3 ruamel.yaml==0.18.17 requests==2.33.0 \
    jinja2==3.1.6 prompt_toolkit==3.0.52 wcwidth==0.2.13 croniter==6.0.0 \
    snowballstemmer==3.1.1 packaging==26.0 Markdown==3.10.2 PyJWT==2.13.0 \
    urllib3==2.7.0 websockets==15.0.1 pathspec==1.1.1 python-multipart==0.0.20 \
    markdown-it-py==4.0.0 mdurl==0.1.2 pygments==2.19.2 charset-normalizer==3.4.4 \
    typing-extensions==4.15.0 tqdm==4.67.1 sniffio==1.3.1 socksio==1.0.0 \
    markupsafe==3.0.2 six==1.17.0 pytz==2025.2 python-dateutil==2.9.0.post0 \
    dulwich==0.22.8
fi

STAGE=$(mktemp -d "$BUILD_ROOT/stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/hermes" "$STAGE/hermes-webui" "$STAGE/python/site-packages"
cp -a "$CPYTHON_ROOT/Lib/." "$STAGE/python/"
for package in acp_adapter agent cron gateway hermes_cli plugins providers tools tui_gateway hermes; do
  [ -d "$HERMES_SOURCE/$package" ] && cp -a "$HERMES_SOURCE/$package" "$STAGE/hermes/"
done
cp -a "$HERMES_SOURCE"/*.py "$STAGE/hermes/" 2>/dev/null || true
cp -a "$ROOT/overlay/hermes/." "$STAGE/hermes/"
"$HOST_PYTHON" "$ROOT/overlay/patches/patch-ios-stability.py" "$STAGE/hermes"
"$HOST_PYTHON" "$ROOT/overlay/patches/patch-agent-sdk-compat.py" "$STAGE/hermes/agent/agent_init.py"
cp "$ROOT/overlay/hermes/agent/legacy_responses.py" "$STAGE/hermes/agent/legacy_responses.py"

if [ -d "$VENDOR_ROOT" ]; then
  cp -a "$VENDOR_ROOT/." "$STAGE/python/site-packages/"
  find "$STAGE/python/site-packages" -type f -name '*.so' -delete
fi
cp -a "$WEBUI_SOURCE/api" "$STAGE/hermes-webui/"
cp -a "$WEBUI_SOURCE/static" "$STAGE/hermes-webui/" 2>/dev/null || true
for module in bootstrap.py server.py mcp_server.py; do
  [ -f "$WEBUI_SOURCE/$module" ] && cp "$WEBUI_SOURCE/$module" "$STAGE/hermes-webui/"
done
"$HOST_PYTHON" "$ROOT/overlay/patches/patch-webui-zip.py" "$STAGE/hermes-webui/api/config.py"
[ -d "$STAGE/hermes/plugins/browser" ] && : > "$STAGE/hermes/plugins/browser/__init__.py"
cp "$ROOT/overlay/python/sitecustomize.py" "$STAGE/python/sitecustomize.py"
cp -a "$ROOT/overlay" "$STAGE/overlay"

"$HOST_PYTHON" - "$STAGE" "$ARCHIVE" <<'PY'
import os, sys, zipfile
root, output = sys.argv[1:]
with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_STORED) as archive:
    seen = set()
    for directory, _, names in os.walk(root):
        for name in sorted(names):
            source = os.path.join(directory, name)
            relative = os.path.relpath(source, root).replace(os.sep, '/')
            if '.git' in relative.split('/'):
                continue
            if relative in seen:
                raise SystemExit(f'duplicate runtime path: {relative}')
            seen.add(relative)
            archive.write(source, relative, compress_type=zipfile.ZIP_STORED)
PY

"$HOST_PYTHON" "$ROOT/build/validate-runtime-zip.py" "$ARCHIVE"
