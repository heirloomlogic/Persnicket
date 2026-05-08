<p align="center">
  <img src="Images/SwiftFormatPlugin-logo@2x.png" alt="SwiftFormatPlugin" width="256">
</p>

# SwiftFormatPlugin

A lightweight SPM plugin that lints and formats Swift source files. Its only dependency is the Swift toolchain's built-in `swift-format` binary.

[![Swift 6.0+](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20|%20Linux-blue.svg)](https://swift.org)
[![CI](https://github.com/HeirloomLogic/SwiftFormatPlugin/actions/workflows/lint.yml/badge.svg)](https://github.com/HeirloomLogic/SwiftFormatPlugin/actions/workflows/lint.yml)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Plugins

| Plugin | Type | What it does |
|---|---|---|
| **SwiftFormatBuildToolPlugin** | Build Tool | Runs `swift-format lint` automatically on every build as a pre-build step. |
| **SwiftFormatCommandPlugin** | Command | Runs `swift-format format --in-place` on demand to reformat source files. |

Both plugins work with Swift Package Manager. On macOS, Xcode project integration is also supported.

## Requirements

- **Swift 6.0+** toolchain that includes `swift-format`
- **macOS**: Xcode 16+ (the plugin invokes `swift-format` via `xcrun`)
- **Linux**: The plugin auto-discovers `swift-format` from the active Swift toolchain. Set `$SWIFT_FORMAT` to an absolute path to override.

The plugin can lint and format targets for any Apple platform (iOS, tvOS, watchOS, visionOS) — it runs on the host machine during the build.

## Installation

Add the package to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/HeirloomLogic/SwiftFormatPlugin", from: "1.5.0"),
]
```

Or in Xcode: **File → Add Package Dependencies** and enter the repository URL.

### Build Tool Plugin (automatic linting)

Apply the plugin to any target you want linted on every build:

```swift
.target(
    name: "MyTarget",
    plugins: [
        .plugin(name: "SwiftFormatBuildToolPlugin", package: "SwiftFormatPlugin"),
    ]
)
```

### Command Plugin (on-demand formatting)

The command plugin registers the SwiftPM built-in `format-source-code` verb. Run it from the command line:

```bash
swift package plugin --allow-writing-to-package-directory format-source-code
```

The plugin runs silently on success — use `git diff` to see what changed.

In Xcode: **right-click your project or package → SwiftFormatCommandPlugin**.

## Configuration

The plugin looks for a `.swift-format` configuration file in your **project root**. If one is found, it will be used for both linting and formatting.

If no `.swift-format` file is present, the plugin falls back to a default configuration. This config is fairly strict, and includes, among other things:

- 4-space indentation, 120-character line length
- Ordered imports and trailing commas
- `NeverForceUnwrap`, `NeverUseForceTry`, and `NeverUseImplicitlyUnwrappedOptionals`
- `AllPublicDeclarationsHaveDocumentation`
- `FileScopedDeclarationPrivacy` set to `private`

To use your own configuration, create a `.swift-format` file in the root of your project. You can generate a starter configuration with the following:

```bash
# macOS
xcrun swift-format dump-configuration > .swift-format

# Linux
swift-format dump-configuration > .swift-format
```

## CI

For CI lint workflows we recommend using [`wearerequired/lint-action`](https://github.com/wearerequired/lint-action) with `swift_format_official` to surface lint violations as inline annotations in pull request diffs. Here's a sample workflow:

```yaml
name: Lint

on:
  pull_request:
  push:
    branches: [main]

permissions:
  checks: write
  contents: read

jobs:
  swift-format-lint:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - name: Link swift-format from Xcode toolchain
        run: ln -s "$(xcrun --find swift-format)" /usr/local/bin/swift-format

      # Optional — only needed if your project doesn't include its own .swift-format
      - name: Resolve swift-format config
        run: |
          if [ ! -f .swift-format ]; then
            swift package resolve
            cp .build/checkouts/SwiftFormatPlugin/.swift-format .swift-format
          fi

      - uses: wearerequired/lint-action@v2
        with:
          swift_format_official: true
          # Optional — omit for lenient mode (warnings only, check still passes)
          swift_format_official_args: "--strict"
```

## Toolchain Compatibility

Match the Swift toolchain on your CI runner to the one on your development machine. Major.minor must align; patch should not matter.

The `swift-format` configuration format can ship breaking changes without a version bump. A `.swift-format` file that parses cleanly under one Swift minor version may fail under another. If local dev and CI drift, you'll see lint failures that can't be reproduced locally.

## How It Works

On **macOS**, the plugins invoke `swift-format` via `/usr/bin/xcrun`, which resolves to the binary in your active Xcode toolchain.

On **Linux**, the plugins auto-discover `swift-format` from the active Swift toolchain. Search order:

1. `$SWIFT_FORMAT` environment variable, if set to an absolute path.
2. Sibling of `swift` on `$PATH` — Swift toolchains ship `swift-format` in the same `bin` directory as `swift`. This is the canonical location and matches what `dirname $(which swift)/swift-format` would produce.
3. `/usr/local/bin/swift-format` and `/usr/bin/swift-format`.
4. `swift-format` directly on `$PATH`.

This means consumers don't need to symlink the binary into `/usr/local/bin` from CI — runners using the official Swift toolchain (e.g. `swift-actions/setup-swift`, the `swift:*` Docker images) work out of the box. If discovery fails, the plugin emits a clear error listing every path it checked instead of failing with a cryptic `env: 'swift-format': No such file or directory`.

The approach buys a few properties:

- Zero compile-time cost: no `swift-syntax` dependency tree to build.
- Always in sync with your toolchain's Swift version.
- No binary artifacts to download or manage.

## Alternatives

A few other tools cover the same ground. The right pick depends on how much control you want versus how much weight you're willing to carry.

### `swift-format` (Apple/SwiftLang)

What this plugin uses. Ships with the Swift toolchain, no extra dependencies, always version-matched to your compiler, opinionated defaults out of the box.

Tradeoffs: less configurable than SwiftLint, smaller rule set, and the configuration format can drift between Swift minor versions (see [Toolchain Compatibility](#toolchain-compatibility)).

### [SwiftLint](https://github.com/realm/SwiftLint)

The most powerful option — ~200+ rules, custom rules, mature autocorrect, large community. Best integrated via [`SwiftLintPlugins`](https://github.com/SimplyDanny/SwiftLintPlugins), which ships SwiftLint as a `.binaryTarget` (prebuilt `SwiftLintBinary.artifactbundle`) so consumers don't pay the `SourceKitten`/`SwiftSyntax` compile cost.

Tradeoffs: the prebuilt binary must be kept version-aligned with your Swift toolchain, and `.swiftlint.yml` exposes hundreds of knobs to tune. Worth the cost when you need that level of control.

### [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) (Nick Lockwood)

A dedicated formatter — fast, mature, focused purely on formatting rather than lint. Extensive rule set, distributable as a binary.

Tradeoffs: a separate tool to install and version-align, and the name collision with Apple's `swift-format` is a frequent source of confusion.

### Why this plugin uses `swift-format`

Lightweight integration is the deciding factor. SwiftLint offers much more control, but `swift-format`'s opinionated defaults get ~99% of the way to a sensible style for most projects. Reaching for the heavier tool only pays off when the remaining 1% actually matters.

## Development

This repo ships shell scripts under `bin/` for working on the plugin itself:

| Script | Purpose |
|---|---|
| `bin/regenerate-embedded-fallback` | Rewrites the embedded `fallbackConfigJSON` literal in all plugin source files from the canonical `.swift-format` at the repo root. |
| `bin/check-shared-plugin-code` | Verifies that the shared plugin infrastructure section is byte-identical across both plugin targets. |

**Editing the default config.** The `.swift-format` file at the repo root is the single source of truth for this plugin's default configuration. If you change it, run `bin/regenerate-embedded-fallback` before committing — the script rewrites the `private let fallbackConfigJSON = """..."""` block in both plugin source files to match.

**Why the duplication exists.** SwiftPM plugin targets cannot share Swift source across targets and cannot carry resources (no `resources:` parameter on `.plugin(...)`, no `PluginContext` API to locate the plugin's own on-disk files), so both plugin source files must embed the fallback as a literal. The generator + CI drift check turns this structural duplication into a managed one: you only ever edit `.swift-format`, and CI fails if the embedded literals are out of sync.

**CI.** `.github/workflows/lint.yml` runs on every pull request and push to `main`. It regenerates the embedded literals and verifies there's no diff (drift check), verifies the shared plugin infrastructure is byte-identical across both targets, then runs `swift-format lint` in strict mode on the plugin's own source.

## Links

- [SwiftFormatPlugin repository](https://github.com/HeirloomLogic/SwiftFormatPlugin)
- [`swift-format` repository](https://github.com/swiftlang/swift-format)
- [`swift-format` rules reference](https://github.com/swiftlang/swift-format/blob/main/Documentation/RuleDocumentation.md)

## License

This project is available under the MIT License. See [LICENSE](LICENSE) for details.
