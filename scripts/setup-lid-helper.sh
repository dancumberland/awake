#!/bin/bash -p
# One-time, explicitly authenticated install/uninstall. Never granted NOPASSWD.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
umask 077
HELPER=/Library/PrivilegedHelperTools/com.dancumberland.awake-lid
STATE=/var/db/com.dancumberland.awake-lid
RULE=/private/etc/sudoers.d/awake-lid
LABEL=com.dancumberland.awake-lid-watchdog
PLIST=/Library/LaunchDaemons/$LABEL.plist
SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../libexec" && pwd -P)/awake-lid-helper"

fail() {
  echo "awake setup: $*" >&2
  exit 1
}
secure_parent() {
  local path="$1" owner mode
  [[ -d "$path" && ! -L "$path" ]] || fail "unsafe or missing directory: $path"
  owner=$(/usr/bin/stat -f '%u' "$path")
  mode=$(/usr/bin/stat -f '%Lp' "$path")
  if [[ "$owner" != 0 ]] || (((8#$mode & 022) != 0)); then
    fail "directory is not root-owned and protected: $path"
  fi
}
[[ $EUID -eq 0 ]] || fail "run with sudo for the one-time install or uninstall"
[[ $# -eq 1 ]] || fail "usage: setup-lid-helper.sh install|uninstall"
secure_parent /Library/PrivilegedHelperTools
secure_parent /Library/LaunchDaemons
secure_parent /private/etc/sudoers.d
secure_parent /private/var/db

if [[ "$1" == uninstall ]]; then
  [[ -f "$STATE/installed" && ! -L "$STATE" ]] || fail "no owned installation receipt found"
  [[ "$(/usr/bin/stat -f '%u:%Lp' "$STATE")" == '0:700' ]] || fail "unsafe state directory"
  # Restore before removing the only password-free recovery route.
  "$HELPER" stop || fail "could not restore sleep; installation retained"
  /bin/launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
  /bin/rm -f "$RULE" "$PLIST" "$HELPER"
  /usr/sbin/visudo -c
  echo "Awake lid helper removed; normal sleep restored. Diagnostic state retained in $STATE."
  exit 0
fi
[[ "$1" == install ]] || fail "unsupported setup operation"
[[ -n "${SUDO_UID:-}" && "${SUDO_UID:-}" =~ ^[0-9]+$ && "${SUDO_UID:-}" != 0 ]] || fail "install using sudo from the account that will run awake"
ACCOUNT=$(/usr/bin/id -un "$SUDO_UID")
[[ "$ACCOUNT" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || fail "account name cannot be represented safely in the narrow sudo rule"
[[ -f "$SOURCE" && ! -L "$SOURCE" ]] || fail "helper source is missing or a symlink"
[[ "$(/usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/ {print $2; exit}')" == 0 ]] || fail "sleep is already disabled; run awake off before setup"
for path in "$HELPER" "$RULE" "$PLIST"; do
  [[ ! -e "$path" && ! -L "$path" ]] || fail "existing file retained: $path (uninstall the old setup before replacement)"
done
/usr/bin/grep -Eq '^[[:space:]]*[@#]includedir[[:space:]]+(/private)?/etc/sudoers.d([[:space:]]|$)' /private/etc/sudoers || fail "sudoers.d is not included; no system policy was changed"
if [[ ! -e "$STATE" && ! -L "$STATE" ]]; then
  /usr/bin/install -d -o root -g wheel -m 700 "$STATE"
fi
[[ -d "$STATE" && ! -L "$STATE" && "$(/usr/bin/stat -f '%u:%Lp' "$STATE")" == '0:700' ]] || fail "unsafe helper state directory"
[[ ! -f "$STATE/token" ]] || fail "an existing helper session is active"
STAGE=$(/usr/bin/mktemp -d "$STATE/install.XXXXXX")
installed=0
complete=0
rollback() {
  if ((installed == 1 && complete == 0)); then
    if [[ -x "$HELPER" ]] && ! "$HELPER" stop; then
      echo "Restoration is pending; helper and watchdog retained for recovery." >&2
      return 0
    fi
    /bin/launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
    /bin/rm -f "$RULE" "$PLIST" "$HELPER"
    echo "Awake setup failed; the new helper, grant, and job were rolled back." >&2
  fi
  /bin/rm -rf "$STAGE"
}
trap rollback EXIT
/usr/bin/install -o root -g wheel -m 755 "$SOURCE" "$STAGE/helper"
printf '%s ALL=(root) NOPASSWD: NOSETENV: %s start *, %s stop, %s status\n' "$ACCOUNT" "$HELPER" "$HELPER" "$HELPER" >"$STAGE/rule"
/bin/chmod 440 "$STAGE/rule"
/usr/sbin/visudo -cf "$STAGE/rule"
cat >"$STAGE/job" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>$HELPER</string><string>recover</string></array>
<key>RunAtLoad</key><true/>
<key>StartInterval</key><integer>5</integer>
<key>ThrottleInterval</key><integer>1</integer>
<key>StandardOutPath</key><string>$STATE/watchdog.log</string>
<key>StandardErrorPath</key><string>$STATE/watchdog.log</string>
</dict></plist>
EOF
/usr/bin/plutil -lint "$STAGE/job"
# Files live only in existing protected root-owned directories.
installed=1
/usr/bin/install -o root -g wheel -m 755 "$STAGE/helper" "$HELPER"
/usr/bin/install -o root -g wheel -m 644 "$STAGE/job" "$PLIST"
/usr/bin/install -o root -g wheel -m 440 "$STAGE/rule" "$RULE"
/usr/sbin/visudo -c
/bin/launchctl bootstrap system "$PLIST"
"$HELPER" status
# Commission both independent expiry and real killed-worker recovery paths.
"$HELPER" start 2 0
/bin/sleep 3
"$HELPER" recover
[[ "$(/usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/ {print $2; exit}')" == 0 ]] || fail "expiry restoration failed"
"$HELPER" start 30 0
TEST_PID=$(/bin/cat "$STATE/pid")
TEST_TOKEN=$(/bin/cat "$STATE/token")
[[ "$TEST_PID" =~ ^[1-9][0-9]*$ ]] || fail "invalid commissioning worker PID"
[[ "$(/bin/ps -ww -p "$TEST_PID" -o command=)" == *" $HELPER _hold $TEST_TOKEN" ]] || fail "commissioning worker identity mismatch"
kill -KILL "$TEST_PID"
for ((attempt = 0; attempt < 15; attempt++)); do
  [[ -f "$STATE/token" ]] || break
  /bin/sleep 1
done
[[ ! -f "$STATE/token" ]] || fail "scheduled watchdog did not recover the killed worker"
[[ "$(/usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/ {print $2; exit}')" == 0 ]] || fail "killed-worker restoration failed"
/usr/bin/grep -q 'RECOVERY: ended, missing, or previous-boot guard detected' "$STATE/events.log" || fail "watchdog event receipt is missing"
echo "Verified: timed expiry and actual scheduled killed-worker recovery; normal sleep restored."
printf 'uid=%s\nhelper_sha256=%s\n' "$SUDO_UID" "$(/usr/bin/shasum -a 256 "$HELPER" | /usr/bin/awk '{print $1}')" >"$STATE/installed"
complete=1
echo "Installed for $ACCOUNT. Future awake lid sessions can use the narrow helper without a password."
echo "Allowed operations: start 1..86400 seconds, stop owned session, status."
echo "Uninstall: sudo $0 uninstall"
