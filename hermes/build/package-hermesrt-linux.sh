#!/usr/bin/env bash
# HermesLink AI-generated glue code; created by cyanmint's coding agent.
# AI-generated content has no copyright holder and is not subject to copyright.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_ROOT=${BUILD_ROOT:-$ROOT/build/linux-runtime}
ASHELL_ROOT=${ASHELL_ROOT:-$BUILD_ROOT/external/a-shell}
AGENT_ROOT=${AGENT_ROOT:-$BUILD_ROOT/external/hermes-agent}
WEBUI_ROOT=${WEBUI_ROOT:-$BUILD_ROOT/external/hermes-webui}
OUTPUT=${OUTPUT:-$ROOT/hermesrt.zip}
HOST_PYTHON=${HOST_PYTHON:-$(command -v python3)}
VENDOR_ROOT=$BUILD_ROOT/vendor
STAGE=$BUILD_ROOT/stage

bash "$ROOT/build/fetch-ashell.sh" "$ASHELL_ROOT"
bash "$ROOT/build/fetch-sources.sh" "$BUILD_ROOT/external"
[ -d "$ASHELL_ROOT/cpython/Lib/encodings" ] || { echo "missing a-Shell CPython standard library" >&2; exit 2; }
[ -f "$AGENT_ROOT/hermes_cli/main.py" ] || { echo "missing Hermes Agent source" >&2; exit 2; }
[ -f "$WEBUI_ROOT/api/config.py" ] || { echo "missing Hermes WebUI source" >&2; exit 2; }
command -v uv >/dev/null 2>&1 || { echo "uv is required" >&2; exit 2; }

rm -rf "$STAGE" "$VENDOR_ROOT"
mkdir -p "$STAGE/python" "$STAGE/python/site-packages" "$STAGE/hermes" "$STAGE/hermes-webui"
cp -a "$ASHELL_ROOT/cpython/Lib/." "$STAGE/python/"
for package in acp_adapter agent cron gateway hermes_cli plugins providers tools tui_gateway hermes; do
  [ -d "$AGENT_ROOT/$package" ] && cp -a "$AGENT_ROOT/$package" "$STAGE/hermes/"
done
cp -a "$AGENT_ROOT"/*.py "$STAGE/hermes/" 2>/dev/null || true
cp -a "$ROOT/overlay/hermes/." "$STAGE/hermes/"
cp -a "$WEBUI_ROOT/api" "$STAGE/hermes-webui/"
cp -a "$WEBUI_ROOT/static" "$STAGE/hermes-webui/" 2>/dev/null || true
for module in bootstrap.py server.py mcp_server.py; do
  [ -f "$WEBUI_ROOT/$module" ] && cp "$WEBUI_ROOT/$module" "$STAGE/hermes-webui/"
done
cp "$ROOT/overlay/python/sitecustomize.py" "$STAGE/python/sitecustomize.py"

uv pip install --target "$VENDOR_ROOT" --python "$HOST_PYTHON" \
  openai==1.3.8 pydantic==1.10.15 'httpx[socks]==0.28.1'
uv pip install --target "$VENDOR_ROOT" --python "$HOST_PYTHON" --no-deps \
  certifi==2026.5.20 python-dotenv==1.2.2 fire==0.7.1 rich==14.3.3 \
  tenacity==9.1.4 pyyaml==6.0.3 ruamel.yaml==0.18.17 requests==2.33.0 \
  jinja2==3.1.6 prompt_toolkit==3.0.52 wcwidth==0.2.13 croniter==6.0.0 \
  packaging==26.0 Markdown==3.10.2 PyJWT==2.13.0 urllib3==2.7.0 \
  websockets==15.0.1 pathspec==1.1.1 pygments==2.19.2 typing-extensions==4.15.0 \
  tqdm==4.67.1 sniffio==1.3.1 socksio==1.0.0 markdown-it-py==4.0.0 mdurl==0.1.2
find "$VENDOR_ROOT" -type f \( -name '*.so' -o -name '*.dylib' -o -name '*.pyd' \) -delete
cp -a "$VENDOR_ROOT/." "$STAGE/python/site-packages/"
cp -a "$ROOT/overlay" "$STAGE/overlay"

python3 - "$STAGE" "$OUTPUT" <<'PY'
import os, sys, zipfile
root, output = sys.argv[1:]
with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_STORED) as archive:
    for directory, _, names in os.walk(root):
        for name in sorted(names):
            source = os.path.join(directory, name)
            relative = os.path.relpath(source, root).replace(os.sep, '/')
            archive.write(source, relative)
PY
python3 - "$OUTPUT" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    names = set(archive.namelist())
    assert 'python/encodings/__init__.py' in names
    assert 'hermes/hermes_cli/main.py' in names
    assert not any(n.endswith(('.so', '.dylib', '.pyd', '.wasm')) for n in names)
PY
printf 'created %s\n' "$OUTPUT"
