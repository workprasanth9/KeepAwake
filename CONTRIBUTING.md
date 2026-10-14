# Contributing

Thanks for looking at KeepAwake. Issues and pull requests are welcome.

## Development

KeepAwake is a Swift package. You need macOS 13 or later and a recent Xcode or Swift toolchain to build the menu bar app and the universal binary. The core library tests also run on the Swift toolchain used by CI.

```bash
swift test
swift run keepawake --help
swift run keepawake schedule "Mon-Fri 09:00-17:00"
swift run keepawake start --duration 1m --dry-run
```

On a Mac:

```bash
make universal
make menu
dist/keepawake --version
```

Do not commit `.build/`, `dist/`, or `Package.resolved`.

## Pull requests

- Keep changes focused.
- Add or update tests for schedule parsing, managed preferences, launchd plists, and command behavior.
- Update `CHANGELOG.md` under the Unreleased heading, or under the version you are releasing.
- Document user facing behavior in `README.md` and `docs/keepawake.1`.
- Do not use em dashes in documentation, comments, or user facing strings. CI rejects them.

## Code style

Match the surrounding Swift. Prefer small types in `KeepAwakeCore` so behavior can be tested without IOKit. Keep macOS only calls behind `canImport` checks when the file also builds on other platforms.

## Releasing

1. Update `KeepAwake.version` in `Sources/KeepAwakeCore/Version.swift`.
2. Move the changelog notes into a version section dated today.
3. Tag `vX.Y.Z` and push the tag. The release workflow attaches the universal binary, the menu bar app, and an unsigned package.
