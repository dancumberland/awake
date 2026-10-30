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
  export CAFFEINATE_LOG="$BATS_TEST_TMPDIR/caffeinate.log"
  export KILLALL_LOG="$BATS_TEST_TMPDIR/killall.log"
  export SAVER_STATE_FILE="$BATS_TEST_TMPDIR/saver_state"
  export AWAKE_LAUNCH_AGENTS_DIR="$BATS_TEST_TMPDIR/LaunchAgents"
  export LAUNCHCTL_LOG="$BATS_TEST_TMPDIR/launchctl.log"
  export DEFAULTS_LOG="$BATS_TEST_TMPDIR/defaults.log"
  echo 300 >"$SAVER_STATE_FILE"
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

  # fake defaults — unlock tests never change the host's preferences.
  cat >"$STUB_BIN/defaults" <<'SH'
#!/bin/bash
echo "defaults $*" >>"$DEFAULTS_LOG"
[[ "$1" == "-currentHost" && "$3" == "com.apple.screensaver" && "$4" == "idleTime" ]] || exit 9
case "$2" in
read) [[ -f "$SAVER_STATE_FILE" ]] || exit 1; cat "$SAVER_STATE_FILE" ;;
write) [[ "${FAIL_SAVER_WRITE:-0}" == 0 ]] || exit 1; echo "$6" >"$SAVER_STATE_FILE" ;;
delete) rm -f "$SAVER_STATE_FILE" ;;
*) exit 9 ;;
esac
SH

  cat >"$STUB_BIN/launchctl" <<'SH'
#!/bin/bash
echo "launchctl $*" >>"$LAUNCHCTL_LOG"
[[ "${FAIL_RECOVERY:-0}" == 0 ]]
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
[[ "$*" == *"awake-lid-guard"* ]] && exit 0
exec "$@"
SH

  # fake pkill / caffeinate — no-ops so nothing real is signalled or launched.
  cat >"$STUB_BIN/pkill" <<'SH'
#!/bin/bash
exit 0
SH
  cat >"$STUB_BIN/caffeinate" <<'SH'
#!/bin/bash
echo "caffeinate $*" >>"$CAFFEINATE_LOG"
if [[ "${KEEP_CAFFEINATE:-0}" == 1 ]]; then exec sleep 60; fi
exit 0
SH
  cat >"$STUB_BIN/killall" <<'SH'
#!/bin/bash
echo "killall $*" >>"$KILLALL_LOG"
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

# --- singular lid-close workflow ---

@test "default mode enables lid-close and records the built-in mic for recovery" {
  stub_mic present
  run "$AWAKE" 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"lid can be CLOSED"* ]]
  [[ "$output" == *"Built-in mic returns after reopening"* ]]
  for _ in {1..20}; do
    [[ -f "$CAFFEINATE_LOG" ]] && break
    sleep 0.05
  done
  grep -q 'caffeinate -dimsu -t 3600' "$CAFFEINATE_LOG"
  grep -q 'sudo -v' "$SUDO_LOG"
  grep -q 'awake-lid-guard 3600 1' "$SUDO_LOG"
  [ -f "$AWAKE_STATE_DIR/lid" ]
  [ -f "$AWAKE_STATE_DIR/mic" ]
}

@test "old mode arguments are rejected so the public workflow stays singular" {
  run "$AWAKE" mic 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"positive number"* ]]
}

@test "status identifies a live lid-close session" {
  livepid=$$
  printf '%s %s\n' "$livepid" 3600 >"$AWAKE_STATE_DIR/pid"
  echo "$(($(date +%s) + 3600))" >"$AWAKE_STATE_DIR/until"
  echo 1 >"$AWAKE_STATE_DIR/lid"

  run "$AWAKE" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"lid can be closed"* ]]
}

# --- help / version ---

@test "--version prints the version and exits 0" {
  run "$AWAKE" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"awake 3.1.0"* ]]
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

# --- built-in mic recovery notice ---
#
# Helpers write stub `system_profiler` / `ioreg` into the per-test PATH dir, so
# these never read the host's real audio devices or lid state.

stub_mic() { # stub_mic present|absent
  if [[ "$1" == "present" ]]; then
    cat >"$STUB_BIN/system_profiler" <<'SH'
#!/bin/bash
cat <<'JSON'
{
  "SPAudioDataType" : [
    {
      "_items" : [
        {
          "_name" : "MacBook Pro Microphone",
          "coreaudio_device_input" : 1,
          "coreaudio_device_transport" : "coreaudio_device_type_builtin"
        }
      ]
    }
  ]
}
JSON
SH
  else
    cat >"$STUB_BIN/system_profiler" <<'SH'
#!/bin/bash
cat <<'JSON'
{
  "SPAudioDataType" : [
    {
      "_items" : [
        {
          "_name" : "MacBook Pro Speakers",
          "coreaudio_device_output" : 2,
          "coreaudio_device_transport" : "coreaudio_device_type_builtin"
        },
        {
          "_name" : "ZoomAudioDevice",
          "coreaudio_device_input" : 2,
          "coreaudio_device_transport" : "coreaudio_device_type_virtual"
        }
      ]
    }
  ]
}
JSON
SH
  fi
  chmod +x "$STUB_BIN/system_profiler"
}

stub_lid() { # stub_lid open|closed
  local state=No
  [[ "$1" == "closed" ]] && state=Yes
  cat >"$STUB_BIN/ioreg" <<SH
#!/bin/bash
echo '    |   "AppleClamshellState" = $state'
SH
  chmod +x "$STUB_BIN/ioreg"
}

stub_lid_close_then_open() {
  export LID_SEQUENCE_FILE="$BATS_TEST_TMPDIR/lid_sequence"
  echo 0 >"$LID_SEQUENCE_FILE"
  cat >"$STUB_BIN/ioreg" <<'SH'
#!/bin/bash
n=$(cat "$LID_SEQUENCE_FILE")
if [[ "$n" -eq 0 ]]; then
  echo '    |   "AppleClamshellState" = Yes'
else
  echo '    |   "AppleClamshellState" = No'
fi
echo $((n + 1)) >"$LID_SEQUENCE_FILE"
SH
  chmod +x "$STUB_BIN/ioreg"
}

stub_guard_clock() {
  export DATE_SEQUENCE_FILE="$BATS_TEST_TMPDIR/date_sequence"
  echo 99 >"$DATE_SEQUENCE_FILE"
  cat >"$STUB_BIN/date" <<'SH'
#!/bin/bash
if [[ "$1" == "+%s" ]]; then
  n=$(cat "$DATE_SEQUENCE_FILE")
  n=$((n + 1))
  echo "$n" >"$DATE_SEQUENCE_FILE"
  echo "$n"
else
  /bin/date "$@"
fi
SH
  chmod +x "$STUB_BIN/date"
}

@test "lid guard restores a missing built-in mic automatically after reopen" {
  stub_mic absent
  stub_lid_close_then_open
  stub_guard_clock

  run env AWAKE_LID_POLL_SECONDS=0 AWAKE_MIC_GRACE_SECONDS=0 "$AWAKE" awake-lid-guard 3 1
  [ "$status" -eq 0 ]
  grep -q 'killall coreaudiod' "$KILLALL_LOG"
  grep -q 'pmset -a disablesleep 1' "$PMSET_LOG"
  grep -q 'pmset -a disablesleep 0' "$PMSET_LOG"
}

@test "mic recovery leaves the audio service alone when the mic returns normally" {
  stub_mic present
  stub_lid open

  run env AWAKE_MIC_GRACE_SECONDS=0 "$AWAKE" awake-mic-recover 1
  [ "$status" -eq 0 ]
  [ ! -f "$KILLALL_LOG" ]
}

@test "off warns when the built-in mic did not come back" {
  echo 1 >"$AWAKE_STATE_DIR/mic" # a built-in mic existed when the session began
  stub_mic absent
  stub_lid open

  run "$AWAKE" off
  [ "$status" -eq 0 ]
  [[ "$output" == *"built-in microphone hasn't come back"* ]]
  [[ "$output" == *"sudo killall coreaudiod"* ]]

  # awake reports the fix, it does not run it
  [ ! -f "$SUDO_LOG" ] || ! grep -q 'killall' "$SUDO_LOG"
  # marker cleared so the next session starts clean
  [ ! -f "$AWAKE_STATE_DIR/mic" ]
}

@test "off stays quiet when the mic came back" {
  echo 1 >"$AWAKE_STATE_DIR/mic"
  stub_mic present
  stub_lid open

  run "$AWAKE" off
  [ "$status" -eq 0 ]
  [[ "$output" != *"microphone"* ]]
}

@test "no mic warning on a Mac that never had a built-in mic" {
  # no mic marker was ever written, because none was found at session start
  stub_mic absent
  stub_lid open

  run "$AWAKE" off
  [ "$status" -eq 0 ]
  [[ "$output" != *"microphone"* ]]
}

@test "no mic warning while the lid is still closed" {
  echo 1 >"$AWAKE_STATE_DIR/mic"
  stub_mic absent
  stub_lid closed # mic is SUPPOSED to be off right now

  run "$AWAKE" off
  [ "$status" -eq 0 ]
  [[ "$output" != *"microphone"* ]]
}

@test "status warns after a session expired on its own and the mic is gone" {
  echo 1 >"$AWAKE_STATE_DIR/mic"
  stub_mic absent
  stub_lid open

  run "$AWAKE" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Not currently caffeinated"* ]]
  [[ "$output" == *"sudo killall coreaudiod"* ]]
  # status is read-only: the marker survives so a later `off` still reports it
  [ -f "$AWAKE_STATE_DIR/mic" ]
}


# --- timed idle-lock prevention ---

teardown() {
  # All recorded workers belong to this test, with isolated state and PATH.
  if [[ -f "$AWAKE_STATE_DIR/unlock/pid" ]]; then
    kill -TERM "$(cat "$AWAKE_STATE_DIR/unlock/pid")" 2>/dev/null || true
  fi
  if [[ -f "$AWAKE_STATE_DIR/pid" ]]; then
    read -r p _ <"$AWAKE_STATE_DIR/pid"
    if [[ "$(ps -p "$p" -o command= 2>/dev/null)" == "sleep 60" ]]; then
      kill "$p" 2>/dev/null || true
    fi
  fi
}

@test "unlock pauses the screen saver and off restores the original timeout" {
  export KEEP_CAFFEINATE=1
  stub_mic absent
  run "$AWAKE" 1 unlock
  [ "$status" -eq 0 ]
  [[ "$output" == *"Idle-lock prevention is on"* ]]
  [ "$(cat "$SAVER_STATE_FILE")" = 0 ]
  run "$AWAKE" status
  [[ "$output" == *"Idle-lock prevention is active"* ]]
  run "$AWAKE" off
  [ "$status" -eq 0 ]
  [ "$(cat "$SAVER_STATE_FILE")" = 300 ]
  [ ! -d "$AWAKE_STATE_DIR/unlock" ]
  ! grep -q 'askForPassword' "$DEFAULTS_LOG"
}

@test "interactive prompt explains hours and accepts 1 unlock" {
  export KEEP_CAFFEINATE=1
  stub_mic absent
  run bash -c 'printf "1 unlock\n" | "$1"' _ "$AWAKE"
  [ "$status" -eq 0 ]
  [[ "$output" == *".5 = 30 minutes"* ]]
  [[ "$output" == *"1 unlock"* ]]
  [ "$(cat "$SAVER_STATE_FILE")" = 0 ]
  run "$AWAKE" off
  [ "$status" -eq 0 ]
}

@test "awake unlock prompts for hours" {
  export KEEP_CAFFEINATE=1
  stub_mic absent
  run bash -c 'printf ".5\n" | "$1" unlock' _ "$AWAKE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Idle-lock prevention is on"* ]]
  run "$AWAKE" off
  [ "$status" -eq 0 ]
}

@test "normal awake does not change screen-saver preferences" {
  stub_mic absent
  run "$AWAKE" 1
  [ "$status" -eq 0 ]
  [ ! -f "$DEFAULTS_LOG" ]
}

@test "replacing unlock mode with normal mode restores the timeout first" {
  export KEEP_CAFFEINATE=1
  stub_mic absent
  run "$AWAKE" 1 unlock
  [ "$status" -eq 0 ]
  run "$AWAKE" 1
  [ "$status" -eq 0 ]
  [ "$(cat "$SAVER_STATE_FILE")" = 300 ]
}

@test "guard restores an absent screen-saver key when the timer expires" {
  rm -f "$SAVER_STATE_FILE"
  mkdir "$AWAKE_STATE_DIR/unlock"
  echo absent >"$AWAKE_STATE_DIR/unlock/original"
  touch "$AWAKE_STATE_DIR/unlock/supervised"
  run "$AWAKE" awake-unlock-guard "$(date +%s)" "$$"
  [ "$status" -eq 0 ]
  [ ! -f "$SAVER_STATE_FILE" ]
  [ -f "$AWAKE_STATE_DIR/unlock/restored" ]
}

@test "guard restores settings if the caffeinate worker crashes" {
  mkdir "$AWAKE_STATE_DIR/unlock"
  echo 600 >"$AWAKE_STATE_DIR/unlock/original"
  touch "$AWAKE_STATE_DIR/unlock/supervised"
  deadpid=$(bash -c 'echo $$')
  run "$AWAKE" awake-unlock-guard "$(($(date +%s) + 60))" "$deadpid"
  [ "$status" -eq 0 ]
  [ "$(cat "$SAVER_STATE_FILE")" = 600 ]
}

@test "off recovers a killed guard without its exit trap" {
  mkdir "$AWAKE_STATE_DIR/unlock"
  echo 300 >"$AWAKE_STATE_DIR/unlock/original"
  echo 99999999 >"$AWAKE_STATE_DIR/unlock/pid"
  echo 0 >"$SAVER_STATE_FILE"
  run "$AWAKE" off
  [ "$status" -eq 0 ]
  [ "$(cat "$SAVER_STATE_FILE")" = 300 ]
}

@test "recovery preserves a user timeout change made during the session" {
  mkdir "$AWAKE_STATE_DIR/unlock"
  echo 300 >"$AWAKE_STATE_DIR/unlock/original"
  echo 900 >"$SAVER_STATE_FILE"
  run "$AWAKE" off
  [ "$status" -eq 0 ]
  [ "$(cat "$SAVER_STATE_FILE")" = 900 ]
}

@test "unlock fails visibly if macOS refuses its preference write" {
  export KEEP_CAFFEINATE=1 FAIL_SAVER_WRITE=1
  stub_mic absent
  run "$AWAKE" 1 unlock
  [ "$status" -ne 0 ]
  [[ "$output" == *"idle-lock prevention could not start"* ]]
  [ "$(cat "$SAVER_STATE_FILE")" = 300 ]
}

@test "invalid extra arguments cannot enable unlock or stop the current session" {
  run "$AWAKE" 1 unlock extra
  [ "$status" -ne 0 ]
  [ ! -f "$DEFAULTS_LOG" ]
  [ ! -f "$SUDO_LOG" ]
}


@test "empty interactive input is rejected without changing preferences" {
  run bash -c 'printf "\n" | "$1"' _ "$AWAKE"
  [ "$status" -ne 0 ]
  [ ! -f "$DEFAULTS_LOG" ]
  [ ! -f "$SUDO_LOG" ]
}

@test "off refuses trailing arguments" {
  run "$AWAKE" off unlock
  [ "$status" -ne 0 ]
  [ ! -f "$SUDO_LOG" ]
}

@test "restoration failure retains recovery state and off retries successfully" {
  mkdir "$AWAKE_STATE_DIR/unlock"
  echo 300 >"$AWAKE_STATE_DIR/unlock/original"
  echo 0 >"$SAVER_STATE_FILE"
  export FAIL_SAVER_WRITE=1
  run "$AWAKE" off
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not restore"* ]]
  [ -f "$AWAKE_STATE_DIR/unlock/original" ]
  export FAIL_SAVER_WRITE=0
  run "$AWAKE" off
  [ "$status" -eq 0 ]
  [ "$(cat "$SAVER_STATE_FILE")" = 300 ]
  [ ! -d "$AWAKE_STATE_DIR/unlock" ]
}


@test "unlock refuses to change preferences without independent recovery" {
  export KEEP_CAFFEINATE=1 FAIL_RECOVERY=1
  stub_mic absent
  run "$AWAKE" 1 unlock
  [ "$status" -ne 0 ]
  [ "$(cat "$SAVER_STATE_FILE")" = 300 ]
  ! grep -q 'write com.apple.screensaver idleTime -int 0' "$DEFAULTS_LOG"
}

@test "independent recovery restores a dead guard and removes its job" {
  mkdir "$AWAKE_STATE_DIR/unlock"
  echo 300 >"$AWAKE_STATE_DIR/unlock/original"
  echo 99999999 >"$AWAKE_STATE_DIR/unlock/pid"
  echo 0 >"$SAVER_STATE_FILE"
  run "$AWAKE" awake-unlock-recovery
  [ "$status" -eq 0 ]
  [ "$(cat "$SAVER_STATE_FILE")" = 300 ]
  [ ! -d "$AWAKE_STATE_DIR/unlock" ]
  grep -q 'bootout' "$LAUNCHCTL_LOG"
}
