# Contributing

Build on macOS 14 or later with Xcode 16 or later. There are no third-party Swift package dependencies.

## Project layout

- `Sources/ColimaCore`: command execution, models, Docker/Colima access, storage measurements, and localization.
- `Sources/ColimaDesk`: SwiftUI windows, sheets, menu bar, and application state.
- `Sources/ColimaProbe`: optional integration checks against a local Colima instance.
- `Tests/ColimaCoreTests`: parsing, command execution, storage accounting, and localization tests.
- `scripts`: app packaging and icon generation.

The Swift package and internal executable retain the original `ColimaDesk` name. The app is named **Colima View**. Its existing bundle identifier is retained to preserve preferences.

## Checks

```sh
swift test --disable-sandbox
bash scripts/build-app.sh
```

Unit tests do not require a running Docker daemon. The optional `colima-desk-check` command reads the local runtime; its `--smoke-test` mode also creates and removes temporary resources.

Please keep Docker commands scoped to the selected profile, use argument arrays rather than interpolating shell commands, and preserve cancellation and stale-response checks for background work.

## Localization

The app defaults to English. UI and app-generated diagnostic messages use `L(...)` and the catalogs in `Sources/ColimaCore/Resources/en.lproj` and `zh-Hans.lproj`.

Add both translations when introducing a new message. Interpolations use indexed placeholders such as `{0}`; the localization tests verify catalog coverage and matching placeholders.

## Changes

For a bug fix, describe how to reproduce the problem and how the change was verified. For a larger feature, start with an issue to discuss scope. Include tests when they protect meaningful behavior rather than copying the implementation.
