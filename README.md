<div align="center">

# awake

*Keep your Mac awake, even with the lid closed.*

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CI](https://github.com/dancumberland/awake/actions/workflows/ci.yml/badge.svg)](https://github.com/dancumberland/awake/actions/workflows/ci.yml)
[![Homebrew tap](https://img.shields.io/badge/homebrew-dancumberland%2Fawake-brightgreen)](https://github.com/dancumberland/homebrew-awake)
![macOS only](https://img.shields.io/badge/macOS-only-000000?logo=apple&logoColor=white)

![awake demo](assets/demo.gif)

</div>

## Why this exists

`caffeinate` is the macOS command for keeping a Mac awake while it sits idle. Menu-bar apps like KeepingYouAwake (6,778 stars) wrap it. None of them can keep the Mac awake once the lid is shut, because closing the lid triggers a firmware-level sleep that no `caffeinate` power assertion can hold off. `awake` handles that case by toggling a systemwide power-management setting for the length of your session, then restoring it when the session ends.

![Diagram comparing caffeinate's idle-sleep coverage with awake's added lid-close coverage](assets/lid-close.svg)

## Install

Homebrew:

```sh
brew tap dancumberland/awake
brew trust dancumberland/awake
brew install awake
```

(Recent Homebrew requires trusting a tap before it will load formulae from it — that's the `brew trust` line, not an optional step.)

Or run the install script, which drops a single file into `/usr/local/bin`:

```sh
curl -fsSL https://raw.githubusercontent.com/dancumberland/awake/master/install.sh | bash
```

## Usage

| Command | What it does |
| --- | --- |
| `awake` | Prompt for how many hours to stay awake |
| `awake 1` | Stay awake for 1 hour |
| `awake .5` | Stay awake for 30 minutes |
| `awake 24` | Stay awake for a full day |
| `awake off` | Let the Mac sleep normally again, including on a lid close |
| `awake status` | Show how much awake-time is left |

`awake --version` prints the version. `awake -h`, `awake --help`, or `awake help` print usage.

A session survives closing the terminal. The process is nohup'd and reparents to launchd, so it keeps running until the timer ends or you run `awake off`.

## What it does with `sudo`, exactly

To hold sleep off while the lid is closed, `awake` changes one systemwide setting that macOS only lets root change. It runs two commands as root, and only these two:

- `pmset -a disablesleep 1` when a session starts, to block clamshell sleep.
- `pmset -a disablesleep 0` when the session ends or the timer runs out, to restore normal sleep.

That covers the entire use of root. This setting applies to the whole system, so macOS asks for an admin password to change it.

You can decline the password prompt. `awake` falls back to idle-only protection. Nothing fails or crashes, and every command works as usual. The Mac stays awake while the lid is open, and closing the lid lets it sleep.

## Battery

> [!WARNING]
> With the lid closed, the Mac runs at full power with the screen off. That drains the battery faster than sleep does. Plug in for long sessions.

## Uninstall

Homebrew:

```sh
brew uninstall awake
```

If you used the install script, remove the file:

```sh
rm -f /usr/local/bin/awake
```

If a session is active, run `awake off` first to restore normal sleep. Once a session ends, `awake` leaves nothing running.

---

<img src="assets/dan.png" alt="Dan Cumberland" width="80" align="left" />

Built by Dan Cumberland. More at [dancumberlandlabs.com](https://dancumberlandlabs.com).

<br clear="left" />
