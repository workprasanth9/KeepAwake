# Changelog

All notable changes to KeepAwake are documented in this file.

The format is based on Keep a Changelog, and this project follows semantic versioning.

## [Unreleased]

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
