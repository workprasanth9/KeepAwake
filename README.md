# KeepAwake

[![CI](https://github.com/workprasanth9/KeepAwake/actions/workflows/ci.yml/badge.svg)](https://github.com/workprasanth9/KeepAwake/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13%2B-black)](https://github.com/workprasanth9/KeepAwake)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)

KeepAwake is a small open source utility for Mac admins. It keeps a Mac from idle sleep with IOKit power assertions, installs the hold as a LaunchAgent or LaunchDaemon, and reads managed preferences so Jamf or another MDM can cap how long a Mac stays awake.

`caffeinate` is still the right tool for a one-off terminal session. KeepAwake is the piece you put in a policy: a weekly schedule, a plist you can read, a status command that shows the assertion, and a kill switch in a configuration profile.

## Requirements

- macOS 13 or later
- An Apple silicon or Intel Mac. Release builds are universal.
- Administrator rights only when you install a system LaunchDaemon or write to `/usr/local/bin`

The menu bar app uses SwiftUI. The command line tool is the part you deploy.

## Install

### Homebrew

```bash
brew tap workprasanth9/tap
brew trust workprasanth9/tap
brew install --cask keepawake
```

Recent Homebrew versions refuse to load a third party tap until you trust it, which is what `brew trust` does. This installs `KeepAwake.app` in `/Applications` and links the `keepawake` command line tool into your Homebrew prefix. The cask clears the download quarantine flag, because the release is ad hoc signed and not notarized.

Update or remove it:

```bash
brew upgrade --cask keepawake
brew uninstall --cask keepawake
brew uninstall --cask --zap keepawake   # also deletes preferences and Application Support files
```

Run `keepawake uninstall` first if you installed a LaunchAgent or LaunchDaemon. Homebrew does not remove launchd jobs.

### Installer package

Each [GitHub release](https://github.com/workprasanth9/KeepAwake/releases/latest) attaches universal builds made by CI:

| File | Contents |
| --- | --- |
| `KeepAwake-<version>.pkg` | `KeepAwake.app` in `/Applications` and `keepawake` in `/usr/local/bin` |
| `keepawake-cli-<version>.pkg` | Only `/usr/local/bin/keepawake`, for Jamf and other MDM policies |
| `keepawake-<version>-macos-universal.zip` | The command line tool, manual page, and license |
| `KeepAwake-<version>-app.zip` | The menu bar app, with the command line tool inside |
| `keepawake-<version>.sha256` | Checksums |

The packages are unsigned. If Gatekeeper blocks one, Control-click it in Finder and choose Open, or allow it in System Settings, Privacy & Security. Sign the packages with your Developer ID before a wide rollout. A binary from the zip may carry a quarantine flag:

```bash
xattr -d com.apple.quarantine /usr/local/bin/keepawake
```

### Build from source

```bash
git clone https://github.com/workprasanth9/KeepAwake.git
cd KeepAwake
swift build -c release
sudo install -m 755 .build/release/keepawake /usr/local/bin/keepawake
```

`make release` builds every release artifact into `dist/`. With Command Line Tools only, the local build may be native arch only. CI builds the universal release.

Optional manual page:

```bash
sudo mkdir -p /usr/local/share/man/man1
sudo cp docs/keepawake.1 /usr/local/share/man/man1/keepawake.1
```

## Quick start

```bash
keepawake start --duration 2h
keepawake status
```

Press Control-C to release a foreground hold. `keepawake start` with no mode holds until you do that.

## Commands

| Command | What it does |
| --- | --- |
| `keepawake start` | Hold an assertion in the foreground |
| `keepawake stop` | Signal KeepAwake processes and unload launchd jobs, leaving plists in place |
| `keepawake resume` | Load installed plists again |
| `keepawake status` | Show jobs, session files, and active power assertions |
| `keepawake install` | Install and bootstrap a LaunchAgent or LaunchDaemon |
| `keepawake uninstall` | Bootout a job and delete its plist |
| `keepawake schedule` | Explain a weekly schedule and the next change |
| `keepawake config` | Show the effective configuration, including managed preferences |
| `keepawake --version` | Print the version |

`--json` prints machine readable output on stdout. `--dry-run` prints the plan or the plist and does not change the system. `--config /path/to/file.plist` adds an extra preferences file. Managed preferences still win.

Exit codes: `0` success, `1` usage or general failure, `2` managed policy denial, `3` assertion failure, `4` launchd or root failure, `5` the requested pid is not running. `stop`, `resume`, and `uninstall` return 0 when there is nothing to do, so a policy can run them twice.

## Usage examples

Stay awake until Control-C:

```bash
keepawake start
```

Stay awake for a duration. A bare number is seconds. Suffixes `s`, `m`, `h`, and `d` can be combined.

```bash
keepawake start --duration 45m
keepawake start --duration 2h
keepawake start --duration 1h30m
keepawake start --duration 90
```

Stay awake until a clock time. If that time already passed today, KeepAwake uses tomorrow and prints the resolved timestamp. A full date that is already past is an error.

```bash
keepawake start --until 18:00
keepawake start --until 5:30pm
keepawake start --until 2026-10-14T18:00
```

Stay awake while an app or process is running. App matching is case insensitive against the process name and against a `.app` bundle name. Process matching is the exact process name from `ps`.

```bash
keepawake start --while-app "zoom.us"
keepawake start --while-process backupd
keepawake start --while-pid 4321
```

If the app is not open yet, KeepAwake waits for it, then releases the assertion after the process has been gone for a few seconds. `--while-pid` fails immediately when that pid is not alive.

Stay awake on a weekly schedule. Quote the specification so the shell keeps it as one argument.

```bash
keepawake start --schedule "Mon-Fri 09:00-17:00"
keepawake schedule "Mon-Fri 09:00-17:00"
```

Preview a plan as JSON:

```bash
keepawake start --duration 30m --dry-run --json
```

## Assertion profiles

With no profile flags, KeepAwake prevents idle display sleep and idle system sleep. That matches the usual "do not dim, do not idle sleep" request. If you pass any of the flags below, only the flags you pass are used.

| Flag | Assertion |
| --- | --- |
| `-d`, `--display` | `PreventUserIdleDisplaySleep` |
| `-i`, `--idle-system` | `PreventUserIdleSystemSleep` |
| `-s`, `--system` | `PreventSystemSleep` |
| `-m`, `--disk` | `PreventDiskIdle` |
| `-u`, `--user-activity` | Declares user activity on a short interval |

```bash
keepawake start --duration 8h --display --idle-system
keepawake start --indefinite --system --reason "Overnight maintenance"
keepawake start --duration 1h --backend caffeinate
```

`--backend` accepts `auto` (default), `iokit`, or `caffeinate`. `auto` uses IOKit and falls back to `/usr/bin/caffeinate` if IOKit returns an error.

`--reason` is the name stored on the assertion. You can see it in `pmset -g assertions` and in `keepawake status`.

## Weekly schedule syntax

A schedule is one or more windows:

```text
Mon-Fri 09:00-17:00
Mon,Wed,Fri 08:30-12:00
Sat,Sun 10:00-14:00
Mon-Fri 09:00-12:00; Mon-Fri 13:00-17:00
all 00:00-24:00
Mon-Fri 22:00-06:00
```

- Days are `Sun`, `Mon`, `Tue`, `Wed`, `Thu`, `Fri`, `Sat`, or the full names. `all` and `every` mean every day.
- Ranges wrap, so `Fri-Mon` is Friday, Saturday, Sunday, and Monday.
- Times are `HH:MM` in local time, or 12-hour times such as `9:00am-5:00pm`.
- The end minute is exclusive. `09:00-17:00` stops at 17:00.
- `00:00-24:00` is a full day. A window cannot start at `24:00`.
- If the end is earlier than the start, the window crosses midnight. `Fri 22:00-06:00` runs from Friday 22:00 until Saturday 06:00.
- An installed schedule job stays running. It holds the assertion only inside a window and sleeps the process until the next boundary. launchd will restart it if it crashes.

Check a specification before you deploy it:

```bash
keepawake schedule "Mon-Fri 22:00-06:00" --json
```

## LaunchAgent and LaunchDaemon

Install a per-user agent. KeepAwake copies the binary into `~/Library/Application Support/KeepAwake/`, writes `~/Library/LaunchAgents/com.keepawake.agent.plist`, and bootstraps `gui/<uid>`.

```bash
keepawake install --schedule "Mon-Fri 09:00-17:00"
```

Logs go to `~/Library/Logs/KeepAwake/keepawake.out.log` and `keepawake.err.log`.

Install a system daemon as root. The plist is `/Library/LaunchDaemons/com.keepawake.daemon.plist`. The binary is copied to `/Library/Application Support/KeepAwake/keepawake`. The domain is `system`.

```bash
sudo keepawake install --daemon --schedule "Mon-Fri 08:00-18:00" --reason "Lab hours"
```

From a root context such as Jamf, name the console user when you want an agent instead of a daemon:

```bash
sudo keepawake install --agent --user ada --no-copy --binary /usr/local/bin/keepawake --duration 8h
```

`--no-copy` makes the plist point at the binary you pass. Use it when a package already installed `/usr/local/bin/keepawake`.

`--keep-alive` restarts the job if it exits. That is the default for indefinite holds, schedules, and process watches. `--duration` and `--until` are one-shot by default: the job runs at load and exits at the deadline. A reboot during a one-shot duration does not resume the remainder. Pass `--keep-alive` only if you want a crash to start the full duration again.

```bash
keepawake install --dry-run --schedule "Mon-Fri 09:00-17:00"
```

The dry run prints the plist and does not call `launchctl`.

## Status, stop, resume, uninstall

```bash
keepawake status
keepawake status --json
keepawake status --keepawake-only
keepawake status --label com.keepawake.agent
```

Status lists:

- Installed KeepAwake plists and whether `launchctl print` shows them loaded
- Session files written while an assertion is held
- System wide assertion counts from `pmset -g assertions`, plus each listed assertion

`PreventUserIdleDisplaySleep`, `PreventUserIdleSystemSleep`, `PreventSystemSleep`, and `PreventDiskIdle` are always shown, even when the count is zero.

```bash
keepawake stop
keepawake resume
keepawake uninstall
sudo keepawake uninstall --daemon --purge
```

`stop` sends SIGTERM to KeepAwake pids recorded in session files, then bootouts the launchd job. The plist remains, so `resume` can load it again. `uninstall` bootouts the job and deletes the plist. `--purge` also deletes the copied binary under Application Support. A normal user cannot change a LaunchDaemon. The command says so and leaves the daemon in place unless you run it as root.

## Managed preferences

Domain: `com.keepawake`

Search order, later files win for each key they contain:

1. `~/Library/Preferences/com.keepawake.plist`
2. The file passed to `--config`, if any
3. `/Library/Managed Preferences/com.keepawake.plist`
4. `/Library/Managed Preferences/<user>/com.keepawake.plist`

```bash
keepawake config
keepawake config --json
```

| Key | Type | Effect |
| --- | --- | --- |
| `Disabled` | bool | When true, `start` and `install` fail with exit code 2 |
| `AllowIndefinite` | bool | When false, indefinite holds and process watches are rejected |
| `MaximumDurationSeconds` | integer | Rejects longer durations, later deadlines, longer schedule windows, and any open ended hold |
| `DefaultSchedule` | string | Used by `install` when you do not pass a mode. Not used by a plain `start` |
| `EnforceSchedule` | bool | When true, only `DefaultSchedule` is allowed |
| `PreventDisplaySleep` | bool | Overrides the default profile when set |
| `PreventIdleSystemSleep` | bool | Overrides the default profile when set |
| `PreventSystemSleep` | bool | Overrides the default profile when set |
| `PreventDiskIdle` | bool | Overrides the default profile when set |
| `DeclareUserActivity` | bool | Overrides the user activity default when set |
| `LockAssertionProfile` | bool | Rejects assertion flags that differ from the managed profile |
| `Reason` | string | Default assertion reason |
| `LockReason` | bool | Rejects a different `--reason` |
| `AllowUserAgent` | bool | When false, `install` without `--daemon` fails |
| `AllowSystemDaemon` | bool | When false, `install --daemon` fails |
| `Backend` | string | `auto`, `iokit`, or `caffeinate` |
| `LockBackend` | bool | Rejects a different `--backend` |

Unset assertion keys keep the built in default (display and idle system sleep prevented). A key that is present replaces that one default. Locked profiles compare the final result with the flags the user passed.

The sample profile in this repo does not set `MaximumDurationSeconds` and does not enforce the schedule, so installing it will not block `keepawake start`. It does set `DefaultSchedule` to `Mon-Fri 08:00-18:00`, which `keepawake install` uses when you omit a mode.

Files:

- `Configuration/com.keepawake.plist` for Jamf Application & Custom Settings, or for a copy into `/Library/Managed Preferences/`
- `Configuration/KeepAwake.mobileconfig` as a configuration profile whose payload type is `com.keepawake`

Example of a stricter lab profile. This is not the sample file. It is the shape you would deploy after you decide the policy:

```xml
<key>AllowIndefinite</key>
<false/>
<key>MaximumDurationSeconds</key>
<integer>28800</integer>
<key>EnforceSchedule</key>
<true/>
<key>DefaultSchedule</key>
<string>Mon-Fri 08:00-18:00</string>
<key>PreventSystemSleep</key>
<false/>
```

With that profile, an 8 hour duration is allowed, an indefinite hold is not, and every start or install uses the weekday schedule.

## Deploy with Jamf Pro

1. Download `keepawake-cli-<version>.pkg` from the latest release, or build it with `make pkg`.
2. Sign the package with your installer certificate. The package only places `/usr/local/bin/keepawake`. It does not load a launchd job.
3. Upload `Configuration/KeepAwake.mobileconfig` as a computer configuration profile, or upload `Configuration/com.keepawake.plist` as an Application & Custom Settings payload for domain `com.keepawake`. Scope it to the Macs that should receive the policy. Edit the schedule before you enforce it.
4. Add `Examples/Jamf/install-keepawake.sh` as a Jamf script. Run it after the package, as root.

Script parameters:

| Parameter | Meaning | Default |
| --- | --- | --- |
| 4 | Mode: `indefinite`, `duration:8h`, `until:18:00`, `schedule:Mon-Fri 08:00-18:00`, `app:zoom.us`, or `process:backupd` | `schedule:Mon-Fri 08:00-18:00` |
| 5 | `daemon` or `agent` | `daemon` |
| 6 | `default`, or a plus-separated list: `display`, `idle`, `system`, `disk`, `user` | `default` |
| 7 | Assertion reason | empty, so KeepAwake uses the managed reason or `KeepAwake` |
| 8 | Binary path | `/usr/local/bin/keepawake` |

An agent target uses the console user from `/dev/console`. If nobody is logged in, the script exits 1. A daemon does not need a console user.

5. Verify with a policy or with SSH:

```bash
keepawake config
keepawake status
```

6. Removal: run `Examples/Jamf/uninstall-keepawake.sh`. It bootouts the default labels, deletes the plists, deletes `/usr/local/bin/keepawake`, and deletes the Application Support copies. Parameter 4 can name one extra label. The script is safe to run when KeepAwake is already gone.

Prefer the daemon for a lab schedule that should apply with no user logged in. Prefer the agent when the hold should follow a specific graphical session. Assertions created by a root daemon are visible to every user in `pmset`.

## Menu bar app

The menu bar app is a SwiftUI extra for interactive use. It is not the MDM install path.

Install it with Homebrew or `KeepAwake-<version>.pkg`, then open KeepAwake from Applications. To build it yourself:

```bash
make menu
cp -R dist/KeepAwake.app /Applications/
open /Applications/KeepAwake.app
```

The menu can hold the Mac awake for 30 minutes, 1 hour, 2 hours, 4 hours, or until you click Stop. It uses the same core as the command line tool, so managed preferences still apply. `LSUIElement` is set, so the app does not take a Dock icon. Quit from the menu.

There is no schedule editor in the menu yet. Deploy schedules with `keepawake install` or Jamf.

## How it works

`start` creates one IOKit assertion per requested type through `IOPMAssertionCreateWithDescription`. When the end time is known, the assertion gets a kernel timeout a short grace period past that deadline, so a hung process does not keep the Mac awake for long after the window. The process also releases the assertion on the deadline, on Control-C, and on SIGTERM. If the process is killed, the kernel drops assertions owned by that pid.

`caffeinate` is the fallback, and the explicit backend when you pass `--backend caffeinate`. The arguments match the profile: `-d`, `-i`, `-m`, `-s`, and `-u`, plus `-t` or `-w` when those apply.

Installed jobs use `launchctl bootstrap` and `launchctl bootout` on macOS 13. Agent plists set `LimitLoadToSessionType` to `Aqua` and `ProcessType` to `Interactive`. While a hold is active, KeepAwake writes a session file under Application Support so `status` and `stop` can find the pid.

## Limitations

- Closing the lid still sleeps most laptops. `--system` asks for `PreventSystemSleep`, the same assertion as `caffeinate -s`. Clamshell behavior depends on the Mac, power adapter, and external displays. KeepAwake does not change `pmset` settings.
- Assertions are suggestions. Thermal limits, a low battery, and an administrator can still sleep the Mac. KeepAwake does not hide its assertions.
- A one-shot `--duration` or `--until` install does not continue after a reboot.
- `--while-app` matches the process name and the `.app` bundle name. Some apps use a different process name than the menu bar title. Check `ps -ax -o ucomm=,command=` if a watch does not see the app.
- The GitHub release packages are unsigned, and the app is ad hoc signed, not notarized. Gatekeeper and Jamf both expect you to sign payloads you deploy at scale.
- The tool targets macOS 13 and later because of the menu bar app and the launchctl bootstrap flow used here.

## Development

```bash
swift test
swift run keepawake --help
make universal
make pkg
```

CI runs on `macos-15-intel`, because the arm64 macOS runners were stuck in the queue. It runs the text check, the tests, a few command smoke tests, and a universal build, then uploads the release artifacts from `Scripts/build-release.sh` as the `keepawake-macos-universal` workflow artifact. Releases are published from that artifact.

See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. User facing text in this repository does not use em dashes.

## Roadmap

- Signed and notarized release artifacts
- Menu bar controls for the installed schedule, plus a notification when a window opens or closes
- A `pkg` postinstall that is still off by default, so a package never starts a hold unless a policy asks for one

## Support

If KeepAwake is useful to you, please [star it on GitHub](https://github.com/workprasanth9/KeepAwake) and share it with a Mac admin friend. It really helps, and it keeps the updates coming.

## License

MIT. See [LICENSE](LICENSE).
