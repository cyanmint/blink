#!/usr/bin/env bash
set -euo pipefail

# Build-time sources. These are deliberately not Git submodules.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEST=${1:-"$ROOT/build/external"}
AGENT_BRANCH=${HERMES_AGENT_BRANCH:-main}
WEBUI_BRANCH=${HERMES_WEBUI_BRANCH:-master}

mkdir -p "$DEST"
fetch() {
  local name=$1 url=$2 branch=$3
  local dir="$DEST/$name"
  if [ ! -d "$dir/.git" ]; then
    rm -rf "$dir"
    git clone --no-checkout --branch "$branch" "$url" "$dir"
  fi
  git -C "$dir" fetch --depth=1 origin "$branch"
  git -C "$dir" checkout --detach "origin/$branch"
}

fetch hermes-agent https://github.com/NousResearch/hermes-agent.git "$AGENT_BRANCH"
fetch hermes-webui https://github.com/nesquena/hermes-webui.git "$WEBUI_BRANCH"
printf 'hermes-agent branch=%s\nhermes-webui branch=%s\n' "$AGENT_BRANCH" "$WEBUI_BRANCH" > "$DEST/SOURCES"
