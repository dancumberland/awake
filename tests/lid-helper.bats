#!/usr/bin/env bats
# Helper logic is sourced as a non-root library with temporary state and stubs.
# These tests cannot write root state, invoke pmset, or install sudo policy.
setup() {
  export HELPER_SOURCE="$BATS_TEST_DIRNAME/../libexec/awake-lid-helper"
  export TEST_STATE="$BATS_TEST_TMPDIR/state"
  mkdir "$TEST_STATE"
  echo 1 >"$TEST_STATE/power"
  cat >"$BATS_TEST_TMPDIR/harness" <<'SH'
source "$HELPER_SOURCE"
STATE="$TEST_STATE"
lock_state() { return 0; }
unlock_state() { :; }
set_sleep() { printf '%s\n' "$1" >"$STATE/power"; }
sleep_disabled() { cat "$STATE/power"; }
log_event() { printf '%s\n' "$*" >>"$STATE/events"; }
guard_running() { return 1; }
now() { echo 100; }
boot_id() { echo current; }
SH
  export HARNESS="$BATS_TEST_TMPDIR/harness"
}

@test "duration parser rejects shell expressions, overflow, zero, and out-of-range values" {
  run /bin/bash -p -c 'source "$HARNESS"; for value in 0 -1 0001 86401 99999999999999999999 "1+1" "1;touch nope" '\''$(touch nope)'\''; do if valid_seconds "$value"; then exit 9; fi; done; valid_seconds 1; valid_seconds 3600; valid_seconds 86400'
  [ "$status" -eq 0 ]
}

@test "invalid start arguments fail before any power operation" {
  run /bin/bash -p -c 'source "$HARNESS"; start_lease "1+1" 0'
  [ "$status" -ne 0 ]
  [ "$(cat "$TEST_STATE/power")" = 1 ]
  [ ! -f "$TEST_STATE/token" ]
}

@test "old guard cannot restore over a replacement lease" {
  echo new >"$TEST_STATE/token"
  run /bin/bash -p -c 'source "$HARNESS"; finish_lease old'
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_STATE/power")" = 1 ]
  [ "$(cat "$TEST_STATE/token")" = new ]
}

@test "current guard restores power and clears its lease" {
  echo current >"$TEST_STATE/token"
  run /bin/bash -p -c 'source "$HARNESS"; finish_lease current'
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_STATE/power")" = 0 ]
  [ ! -f "$TEST_STATE/token" ]
}

@test "failed restoration retains state for watchdog retry" {
  echo current >"$TEST_STATE/token"
  run /bin/bash -p -c 'source "$HARNESS"; set_sleep() { return 1; }; finish_lease current'
  [ "$status" -ne 0 ]
  [ -f "$TEST_STATE/token" ]
}

@test "a different user cannot stop another account's lease" {
  echo current >"$TEST_STATE/token"
  echo 502 >"$TEST_STATE/owner"
  run env SUDO_UID=501 /bin/bash -p -c 'source "$HARNESS"; stop_lease'
  [ "$status" -ne 0 ]
  [ "$(cat "$TEST_STATE/power")" = 1 ]
  [ -f "$TEST_STATE/token" ]
}

@test "watchdog recovers a missing guard" {
  echo current >"$TEST_STATE/token"
  echo current >"$TEST_STATE/boot"
  echo 200 >"$TEST_STATE/deadline"
  run /bin/bash -p -c 'source "$HARNESS"; recover_lease'
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_STATE/power")" = 0 ]
  grep -q 'RECOVERY:' "$TEST_STATE/events"
}

@test "watchdog leaves a live current-boot lease alone" {
  echo current >"$TEST_STATE/token"
  echo current >"$TEST_STATE/boot"
  echo 200 >"$TEST_STATE/deadline"
  run /bin/bash -p -c 'source "$HARNESS"; guard_running() { return 0; }; recover_lease'
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_STATE/power")" = 1 ]
  [ -f "$TEST_STATE/token" ]
}

@test "previous-boot lease restores even if a PID is reused" {
  echo current >"$TEST_STATE/token"
  echo old >"$TEST_STATE/boot"
  echo 200 >"$TEST_STATE/deadline"
  # guard_running is false to avoid signalling any real process in this unit test.
  run /bin/bash -p -c 'source "$HARNESS"; recover_lease'
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_STATE/power")" = 0 ]
  [ ! -f "$TEST_STATE/token" ]
}

@test "privileged-mode shebang ignores BASH_ENV startup code" {
  printf 'touch "%s"\n' "$BATS_TEST_TMPDIR/injected" >"$BATS_TEST_TMPDIR/evil"
  run env BASH_ENV="$BATS_TEST_TMPDIR/evil" "$HELPER_SOURCE" status
  [ "$status" -ne 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/injected" ]
}

@test "direct non-root helper use is refused" {
  run "$HELPER_SOURCE" start 1 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires root"* ]]
}
