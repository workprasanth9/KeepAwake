# Changelog

All notable changes to KeepAwake are documented in this file.

The format is based on Keep a Changelog, and this project follows semantic versioning.

## [Unreleased]

## [1.0.0] - 2026-10-27

First public release.

### Added

- `KeepAwake-<version>.pkg` installs the menu bar app in /Applications and the command line tool in /usr/local/bin
- Installer thank you page with a getting started note
- `keepawake-<version>-macos-universal.zip` with the tool, manual page, and license
- The menu bar app bundles the command line tool, so the Homebrew cask can link it
- Homebrew cask: `brew install --cask workprasanth9/tap/keepawake`
- `make release` and `Scripts/build-release.sh`

### Changed

- The command line only package is now `keepawake-cli-<version>.pkg` and is a product archive
- CI runs on `macos-15-intel` and uploads the release artifacts. Releases are published from the CI build instead of a tag workflow

## [0.1.0] - 2026-10-14

### Added

- `keepawake` command line tool with `start`, `stop`, `resume`, `status`, `install`, `uninstall`, `schedule`, and `config`
- IOKit power assertions, with an automatic fallback to `caffeinate`
- Hold modes: indefinite, duration, until a time, while an app or process runs, and a weekly schedule
- Per-user LaunchAgent install and optional system LaunchDaemon install
- Managed preferences domain `com.keepawake`, including a sample plist and configuration profile
- Jamf Pro install and uninstall policy scripts
- SwiftUI menu bar app
- Universal binary build, installer package script, and a tag-triggered GitHub release
