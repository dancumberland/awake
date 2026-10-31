# Contributing

`bin/awake` is the main Bash script. Optional privileged setup lives in `libexec/awake-lid-helper` and `scripts/setup-lid-helper.sh`. Small, focused changes are easiest to review — if you're planning something bigger, open an issue first so we can talk through the approach.

## Setup

```sh
brew install shellcheck shfmt bats-core
```

## Before opening a PR

```sh
shellcheck bin/awake libexec/awake-lid-helper scripts/setup-lid-helper.sh
shfmt -i 2 -d bin/awake libexec/awake-lid-helper scripts/setup-lid-helper.sh
bats tests/
```

All three run in CI on macOS, so a clean local run should mean a clean check.

## Making a change

- Keep `bin/awake` POSIX-friendly bash, no external dependencies beyond what macOS ships (plus `caffeinate` and `pmset`, both built in).
- If you touch the lid-close (`disablesleep`) path, test the reboot-recovery case by hand: `sudo pmset -a disablesleep 1`, delete `~/.cache/awake/lid`, then confirm `awake off` still restores `SleepDisabled 0`. Bats can't exercise this safely since it needs real root and real system state.
- Match the existing output style — short, a little charming, no more than one line per state change.

## Reporting a bug

Include `awake --version`, your macOS version, and the output of `awake status`. If it's related to sleep not restoring, also include `pmset -g | grep SleepDisabled`.
