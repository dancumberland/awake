#!/bin/bash
# Standalone release install; optional root-helper setup remains a separate opt-in.
set -euo pipefail
RELEASE=4.1.0
PREFIX="${AWAKE_INSTALL_PREFIX:-/usr/local}"
[[ "$(uname -s)" == Darwin ]] || {
  echo 'awake only runs on macOS.' >&2
  exit 1
}
[[ "$PREFIX" == /* && -d "$PREFIX" ]] || {
  echo 'Installation prefix must be an existing absolute directory.' >&2
  exit 1
}
BIN="$PREFIX/bin/awake"
SUPPORT="$PREFIX/libexec/awake"
[[ ! -L "$BIN" ]] || {
  echo "$BIN is a symlink; update it with its package manager or choose AWAKE_INSTALL_PREFIX." >&2
  exit 1
}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://github.com/dancumberland/awake/archive/refs/tags/v$RELEASE.tar.gz" -o "$TMP/release.tar.gz"
tar -xzf "$TMP/release.tar.gz" -C "$TMP"
SOURCE="$TMP/awake-$RELEASE"
for file in bin/awake libexec/awake-lid-helper scripts/setup-lid-helper.sh; do
  [[ -f "$SOURCE/$file" && ! -L "$SOURCE/$file" ]] || {
    echo "Release is missing $file; nothing installed." >&2
    exit 1
  }
done
needs_admin=0
for dir in "$PREFIX" "$PREFIX/bin" "$PREFIX/libexec" "$SUPPORT"; do
  if [[ -d "$dir" && ! -w "$dir" ]]; then needs_admin=1; fi
done
if ((needs_admin == 1)); then
  echo "Installing files under $PREFIX needs admin access; this does not enable the optional lid helper."
  sudo -v
fi
install_files() {
  if ((needs_admin == 1)); then sudo /usr/bin/install "$@"; else /usr/bin/install "$@"; fi
}
install_files -d -m 755 "$PREFIX/bin" "$SUPPORT"
install_files -m 755 "$SOURCE/libexec/awake-lid-helper" "$SUPPORT/awake-lid-helper"
install_files -m 755 "$SOURCE/scripts/setup-lid-helper.sh" "$SUPPORT/setup-lid-helper.sh"
install_files -m 755 "$SOURCE/bin/awake" "$BIN"
echo "Installed awake $RELEASE at $BIN."
echo 'Optional one-time password-free lid setup: awake setup'
echo 'No root helper or password-free grant is installed until you opt in.'
