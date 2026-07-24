#!/bin/bash
# Installs awake to /usr/local/bin. Safe to re-run.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "awake only runs on macOS." >&2
  exit 1
fi

REPO_RAW="https://raw.githubusercontent.com/dancumberland/awake/master/bin/awake"
DEST="/usr/local/bin/awake"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "Downloading awake..."
curl -fsSL "$REPO_RAW" -o "$TMP"
chmod +x "$TMP"

if [[ -w "$(dirname "$DEST")" ]]; then
  mv "$TMP" "$DEST"
else
  echo "Need sudo to write to $DEST"
  sudo mv "$TMP" "$DEST"
fi

echo "Installed. Run: awake --version"
