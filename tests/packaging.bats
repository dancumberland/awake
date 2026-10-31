#!/usr/bin/env bats
# Distribution checks use a local release fixture, isolated prefix, and fake sudo.
setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  export AWAKE_INSTALL_PREFIX="$BATS_TEST_TMPDIR/prefix"
  export AWAKE_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export PACKAGE_SUDO_LOG="$BATS_TEST_TMPDIR/sudo.log"
  export PACKAGE_FIXTURE="$BATS_TEST_TMPDIR/release.tgz"
  mkdir -p "$AWAKE_INSTALL_PREFIX" "$BATS_TEST_TMPDIR/stubs" "$BATS_TEST_TMPDIR/awake-4.1.0/bin" "$BATS_TEST_TMPDIR/awake-4.1.0/libexec" "$BATS_TEST_TMPDIR/awake-4.1.0/scripts"
  cp "$REPO/bin/awake" "$BATS_TEST_TMPDIR/awake-4.1.0/bin/awake"
  cp "$REPO/libexec/awake-lid-helper" "$BATS_TEST_TMPDIR/awake-4.1.0/libexec/awake-lid-helper"
  cp "$REPO/scripts/setup-lid-helper.sh" "$BATS_TEST_TMPDIR/awake-4.1.0/scripts/setup-lid-helper.sh"
  tar -czf "$PACKAGE_FIXTURE" -C "$BATS_TEST_TMPDIR" awake-4.1.0
  cat >"$BATS_TEST_TMPDIR/stubs/curl" <<'SH'
#!/bin/bash
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -o ]]; then cp "$PACKAGE_FIXTURE" "$2"; exit 0; fi
  shift
done
exit 1
SH
  cat >"$BATS_TEST_TMPDIR/stubs/sudo" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$PACKAGE_SUDO_LOG"
[[ "$1" != -n ]] # No installed helper in these isolated distribution checks.
SH
  chmod +x "$BATS_TEST_TMPDIR/stubs/"*
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
}

@test "standalone release contains the command and setup support files" {
  run "$REPO/install.sh"
  [ "$status" -eq 0 ]
  [ -x "$AWAKE_INSTALL_PREFIX/bin/awake" ]
  [ -x "$AWAKE_INSTALL_PREFIX/libexec/awake/awake-lid-helper" ]
  [ -x "$AWAKE_INSTALL_PREFIX/libexec/awake/setup-lid-helper.sh" ]
  [ ! -f "$PACKAGE_SUDO_LOG" ]
  run "$AWAKE_INSTALL_PREFIX/bin/awake" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"awake 4.1.0"* ]]
  run "$AWAKE_INSTALL_PREFIX/bin/awake" setup
  [ "$status" -eq 0 ]
  grep -q "$AWAKE_INSTALL_PREFIX/libexec/awake/setup-lid-helper.sh install" "$PACKAGE_SUDO_LOG"
}

@test "packaged setup resolves its adjacent helper before refusing non-root install" {
  run "$REPO/install.sh"
  [ "$status" -eq 0 ]
  run "$AWAKE_INSTALL_PREFIX/libexec/awake/setup-lid-helper.sh" install
  [ "$status" -ne 0 ]
  [[ "$output" == *"run with sudo"* ]]
  [[ "$output" != *"No such file"* ]]
}

@test "Homebrew layout locates both helper and installer in libexec" {
  mkdir -p "$AWAKE_INSTALL_PREFIX/bin" "$AWAKE_INSTALL_PREFIX/libexec"
  cp "$REPO/bin/awake" "$AWAKE_INSTALL_PREFIX/bin/awake"
  cp "$REPO/libexec/awake-lid-helper" "$AWAKE_INSTALL_PREFIX/libexec/awake-lid-helper"
  cp "$REPO/scripts/setup-lid-helper.sh" "$AWAKE_INSTALL_PREFIX/libexec/setup-lid-helper.sh"
  run "$AWAKE_INSTALL_PREFIX/bin/awake" setup
  [ "$status" -eq 0 ]
  grep -q "$AWAKE_INSTALL_PREFIX/libexec/setup-lid-helper.sh install" "$PACKAGE_SUDO_LOG"
  run "$AWAKE_INSTALL_PREFIX/libexec/setup-lid-helper.sh" install
  [ "$status" -ne 0 ]
  [[ "$output" == *"run with sudo"* ]]
}

@test "incomplete release cannot replace an existing command" {
  rm "$BATS_TEST_TMPDIR/awake-4.1.0/libexec/awake-lid-helper"
  tar -czf "$PACKAGE_FIXTURE" -C "$BATS_TEST_TMPDIR" awake-4.1.0
  mkdir "$AWAKE_INSTALL_PREFIX/bin"
  echo original >"$AWAKE_INSTALL_PREFIX/bin/awake"
  run "$REPO/install.sh"
  [ "$status" -ne 0 ]
  [ "$(cat "$AWAKE_INSTALL_PREFIX/bin/awake")" = original ]
}

@test "standalone installer refuses to overwrite another installation's symlink" {
  mkdir "$AWAKE_INSTALL_PREFIX/bin"
  echo original >"$BATS_TEST_TMPDIR/other-command"
  ln -s "$BATS_TEST_TMPDIR/other-command" "$AWAKE_INSTALL_PREFIX/bin/awake"
  run "$REPO/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"is a symlink"* ]]
  [ -L "$AWAKE_INSTALL_PREFIX/bin/awake" ]
  [ "$(cat "$BATS_TEST_TMPDIR/other-command")" = original ]
}
