# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
