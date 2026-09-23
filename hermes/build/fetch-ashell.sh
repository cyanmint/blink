#!/usr/bin/env bash
# HermesLink AI-generated glue code; created by cyanmint's coding agent.
# AI-generated content has no copyright holder and is not subject to copyright.
set -euo pipefail

# Fetch a-Shell as a disposable build input. The checkout is never packaged
# into hermesrt.zip; its source and submodule licenses remain applicable.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEST=${1:-"$ROOT/build/external/a-shell"}
ASHELL_COMMIT=${ASHELL_COMMIT:-8f7d318839db60f78792b37a462fc4f09d0796c9}
ASHELL_URL=${ASHELL_URL:-https://github.com/holzschu/a-shell.git}

mkdir -p "$(dirname "$DEST")"
if [ ! -d "$DEST/.git" ]; then
  rm -rf "$DEST"
  git clone --no-checkout "$ASHELL_URL" "$DEST"
fi
git -C "$DEST" fetch --depth=1 origin "$ASHELL_COMMIT"
git -C "$DEST" checkout --detach "$ASHELL_COMMIT"

# a-Shell records SSH submodule URLs. Rewrite only for this fetch command so
# the build works in clean CI environments without an SSH key.
git -C "$DEST" \
  -c url.https://github.com/.insteadOf=git@github.com: \
  submodule update --init --depth=1

EXPECTED_CPYTHON=$(git -C "$DEST" ls-tree "$ASHELL_COMMIT" cpython | awk '{print $3}')
EXPECTED_SWIFTTERM=$(git -C "$DEST" ls-tree "$ASHELL_COMMIT" SwiftTerm | awk '{print $3}')
[ "$(git -C "$DEST/cpython" rev-parse HEAD)" = "$EXPECTED_CPYTHON" ]
[ "$(git -C "$DEST/SwiftTerm" rev-parse HEAD)" = "$EXPECTED_SWIFTTERM" ]
printf 'a-shell=%s\ncpython=%s\nSwiftTerm=%s\n' \
  "$ASHELL_COMMIT" "$EXPECTED_CPYTHON" "$EXPECTED_SWIFTTERM" > "$DEST/SOURCES"
