#!/usr/bin/env bats
#
# Tests for `awake`.
#
# SAFETY: anything that could touch real system sleep state or ask for an admin
# password is STUBBED through a fake PATH dir created per-test. These tests
# never run the real `sudo`, never call the host's real `pmset`, and never
# modify the machine's SleepDisabled setting. `AWAKE_STATE_DIR` is redirected to
# a temp dir so the real ~/.cache/awake is never touched either.

setup() {
  AWAKE="${BATS_TEST_DIRNAME}/../bin/awake"

  # Per-test isolated state + stub dirs.
  export AWAKE_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$AWAKE_STATE_DIR"

  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"

  # The fake pmset keeps its pretend SleepDisabled value in a file; logs record
  # what got called so tests can assert on real-command avoidance.
  export PMSET_STATE_FILE="$BATS_TEST_TMPDIR/pmset_state"
  export PMSET_LOG="$BATS_TEST_TMPDIR/pmset.log"
  export SUDO_LOG="$BATS_TEST_TMPDIR/sudo.log"
  echo 0 >"$PMSET_STATE_FILE" # default: sleep NOT disabled

  # fake pmset — reads/writes PMSET_STATE_FILE only, never the real host.
  cat >"$STUB_BIN/pmset" <<'SH'
#!/bin/bash
echo "pmset $*" >>"$PMSET_LOG"
if [[ "$1" == "-g" ]]; then
  printf ' SleepDisabled\t\t%s\n' "$(cat "$PMSET_STATE_FILE" 2>/dev/null || echo 0)"
  exit 0
fi
if [[ "$1" == "-a" && "$2" == "disablesleep" ]]; then
  echo "$3" >"$PMSET_STATE_FILE"
  exit 0
fi
exit 0
SH

  # fake sudo — logs the call, then runs the remaining command under the stub
  # PATH. The real sudo is never invoked and no password is ever requested.
  cat >"$STUB_BIN/sudo" <<'SH'
#!/bin/bash
echo "sudo $*" >>"$SUDO_LOG"
if [[ "$1" == "-v" || "$1" == "-n" ]]; then
  shift || true
  [[ $# -eq 0 ]] && exit 0
fi
exec "$@"
SH

  # fake pkill / caffeinate — no-ops so nothing real is signalled or launched.
  cat >"$STUB_BIN/pkill" <<'SH'
#!/bin/bash
exit 0
SH
  cat >"$STUB_BIN/caffeinate" <<'SH'
#!/bin/bash
exit 0
SH

  chmod +x "$STUB_BIN"/*
  export PATH="$STUB_BIN:$PATH"
}

# --- Bug 1: `awake off` restores sleep from LIVE state, not the lid file ---

@test "off restores SleepDisabled to 0 even when no lid file is tracked" {
  echo 1 >"$PMSET_STATE_FILE" # system is stuck disabled (post-reboot ghost)
  # deliberately NO pid/until/lid files exist

  run "$AWAKE" off
  [ "$status" -eq 0 ]
  [[ "$output" == *"Caffeine off"* ]]

  # live state was actually restored, via the stubbed sudo pmset
  [ "$(cat "$PMSET_STATE_FILE")" -eq 0 ]
  grep -q 'pmset -a disablesleep 0' "$SUDO_LOG"
}

@test "off is password-free when sleep is not disabled" {
  echo 0 >"$PMSET_STATE_FILE"

  run "$AWAKE" off
  [ "$status" -eq 0 ]
  [[ "$output" == *"Caffeine off"* ]]

  # nothing needed restoring, so sudo was never reached at all
  [ ! -f "$SUDO_LOG" ]
}

# --- stale-state self-healing ---

@test "stale dead-PID session is cleaned up before status" {
  deadpid=$(bash -c 'echo $$') # this subshell has already exited -> pid is dead
  printf '%s %s\n' "$deadpid" 3600 >"$AWAKE_STATE_DIR/pid"
  echo "$(($(date +%s) + 3600))" >"$AWAKE_STATE_DIR/until"

  run "$AWAKE" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Not currently caffeinated"* ]]
  [ ! -f "$AWAKE_STATE_DIR/pid" ]
  [ ! -f "$AWAKE_STATE_DIR/until" ]
}

@test "expired-timer session is cleaned up before status" {
  livepid=$$ # a definitely-alive pid, but the timer is in the past
  printf '%s %s\n' "$livepid" 3600 >"$AWAKE_STATE_DIR/pid"
  echo "$(($(date +%s) - 60))" >"$AWAKE_STATE_DIR/until"

  run "$AWAKE" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Not currently caffeinated"* ]]
  [ ! -f "$AWAKE_STATE_DIR/pid" ]
  [ ! -f "$AWAKE_STATE_DIR/until" ]
}

# --- status truth-telling ---

@test "status reports not caffeinated on a clean slate" {
  run "$AWAKE" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Not currently caffeinated"* ]]
}

@test "status warns when sleep is disabled but nothing is tracked" {
  echo 1 >"$PMSET_STATE_FILE"

  run "$AWAKE" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Not currently caffeinated"* ]]
  [[ "$output" == *"Sleep is disabled system-wide"* ]]
}

@test "status reports a live tracked session" {
  livepid=$$
  printf '%s %s\n' "$livepid" 3600 >"$AWAKE_STATE_DIR/pid"
  echo "$(($(date +%s) + 3600))" >"$AWAKE_STATE_DIR/until"

  run "$AWAKE" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Awake for"* ]]
}

# --- help / version ---

@test "--version prints the version and exits 0" {
  run "$AWAKE" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"awake 1.0.0"* ]]
}

@test "-h prints help and exits 0" {
  run "$AWAKE" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"keep this Mac awake"* ]]
}

@test "--help and help aliases exit 0" {
  run "$AWAKE" --help
  [ "$status" -eq 0 ]
  run "$AWAKE" help
  [ "$status" -eq 0 ]
}

# --- input validation (preserve existing behavior) ---

@test "non-numeric hours is rejected" {
  run "$AWAKE" abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"positive number"* ]]
}

@test "negative hours is rejected" {
  run "$AWAKE" -3
  [ "$status" -ne 0 ]
  [[ "$output" == *"positive number"* ]]
}

@test "zero hours (0.0) is rejected" {
  run "$AWAKE" 0.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"positive number"* ]]
}

# --- platform guard ---

@test "non-macOS platform is refused" {
  cat >"$STUB_BIN/uname" <<'SH'
#!/bin/bash
echo Linux
SH
  chmod +x "$STUB_BIN/uname"

  run "$AWAKE" status
  [ "$status" -ne 0 ]
  [[ "$output" == *"only works on macOS"* ]]
}
