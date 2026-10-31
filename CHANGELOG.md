# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [4.1.0] - 2026-10-31

### Added
- Homebrew and standalone distributions include the optional helper and setup files; setup discovery supports source and packaged layouts.
- Optional `awake setup` installs a root-owned fixed-function lid helper and an account-specific NOPASSWD rule for bounded start, stop, and status operations.
- Helper-backed lid sessions require no recurring admin prompt and are limited to 24 hours. `awake uninstall-helper` removes the grant and installed helper/job after restoring sleep.
- Root-only lease state, process/token/boot binding, timed restoration, and a separately scheduled recovery watchdog. Installer commissions real expiry and killed-worker recovery.

## [4.0.0] - 2026-10-30

### Changed
- Default `awake` and `awake [hours] unlock` are password-free and leave lid sleep under macOS control.
- Lid-close sleep suppression now requires the explicit `lid` option, e.g. `awake 1 lid` or `awake 1 unlock lid`; only this mode asks for admin access.
- Ordinary sessions fail without prompting if an existing privileged sleep override requires cleanup. `awake off` retains that recovery path.
- Help and interactive hints distinguish password-free idle protection from privileged laptop-only lid suppression. One short laptop-only physical test verified an unlocked session, native GUI actions, screenshots, and automatic restoration with `awake .02 unlock lid`; broader hardware/app and long-duration behavior remains unverified.

## [3.1.0] - 2026-10-30

### Added
- Optional `awake 1 unlock`, `awake unlock 1`, and `awake unlock` mode to pause the idle screen saver for the session without changing password requirements.
- Interactive duration examples and support for entering `1 unlock` at the prompt.
- Exact timeout restoration on expiry, off, replacement, or caffeinate exit; independent temporary launchd recovery after a killed guard or reboot, with synchronous recovery on the next invocation as well. User timeout changes are preserved.
- Idle-lock mode status and visible startup/recovery failures.

## [3.0.0] - 2026-08-03

### Changed
- Restored the singular workflow: `awake [hours]` once again includes lid-closed operation by default. The separate `mic` and `lid` modes are removed.
- Awake now watches for the lid to reopen and automatically restarts the Mac audio service only when the built-in microphone fails to return after a grace period.
- The built-in microphone remains physically unavailable while the lid is shut; use an external microphone for audio input in that state.

## [2.0.0] - 2026-07-30

### Changed
- `awake [hours]` now defaults to lid-open operation so the built-in microphone and camera remain available. The display may sleep and no administrator password is required.
- Lid-closed operation is now explicit: use `awake lid [hours]`. The built-in microphone and camera remain unavailable while the lid is physically closed, so that mode requires external devices.
- `awake mic [hours]` remains as a compatible alias for the new default.

## [1.1.0] - 2026-07-30

### Added
- `awake mic [hours]` — keep the Mac running with its built-in microphone available while the lid stays open. The display may sleep and no administrator password is required.

## [1.0.0]

Initial public release.

### Added
- `awake [hours]` — keep the Mac awake for a set number of hours, idle-sleep and lid-close both included.
- `awake off` — restore normal sleep. Self-heals a stuck `disablesleep` state even if the tracked session was lost (e.g. after a reboot).
- `awake status` — show remaining awake time, and warn if the system's sleep setting is disabled with no active session.
- Built-in microphone recovery: macOS turns the built-in microphone and camera off while the lid is closed and occasionally fails to re-register the microphone on wake. `awake off` and `awake status` notice and print the `sudo killall coreaudiod` command that restores it. Stays quiet on Macs with no built-in microphone, while the lid is still closed, and when the microphone came back on its own.
- `awake --version`, `awake --help`.
- Runs as a detached background process, so a session survives closing the terminal.
- CI: shellcheck, shfmt, and bats tests on macOS.
