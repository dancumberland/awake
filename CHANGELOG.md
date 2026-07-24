# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Documentation
- Note that macOS turns off the built-in microphone and camera while the lid is closed, and give the `sudo killall coreaudiod` recovery for when the microphone doesn't come back on its own. No behavior change — `awake` never touched audio.

## [1.0.0]

Initial public release.

### Added
- `awake [hours]` — keep the Mac awake for a set number of hours, idle-sleep and lid-close both included.
- `awake off` — restore normal sleep. Self-heals a stuck `disablesleep` state even if the tracked session was lost (e.g. after a reboot).
- `awake status` — show remaining awake time, and warn if the system's sleep setting is disabled with no active session.
- `awake --version`, `awake --help`.
- Runs as a detached background process, so a session survives closing the terminal.
- CI: shellcheck, shfmt, and bats tests on macOS.
