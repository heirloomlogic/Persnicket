<p align="center">
  <img src="Images/SwiftFormatPlugin-logo@2x.png" alt="SwiftFormatPlugin" width="256">
</p>

<h1 align="center">SwiftFormatPlugin</h1>

<p align="center">
A lightweight SPM plugin that lints and formats Swift source files. Its only dependency is the Swift toolchain's built-in <code>swift-format</code> binary.
</p>

<p align="center">

[![Swift 6.0+](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20|%20Linux-blue.svg)](https://swift.org)
[![CI](https://github.com/HeirloomLogic/SwiftFormatPlugin/actions/workflows/lint.yml/badge.svg)](https://github.com/HeirloomLogic/SwiftFormatPlugin/actions/workflows/lint.yml)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</p>

## Plugins

| Plugin | Type | What it does |
|---|---|---|
| **SwiftFormatBuildToolPlugin** | Build Tool | Runs `swift-format lint` automatically on every build as a pre-build step. |
| **SwiftFormatCommandPlugin** | Command | Runs `swift-format format --in-place` on demand to reformat source files. |

Both plugins work with Swift Package Manager. On macOS, Xcode project integration is also supported.

## Requirements

- **Swift 6.0+** toolchain that includes `swift-format`
- **macOS**: Xcode 16+ (the plugin invokes `swift-format` via `xcrun`)
- **Linux**: `swift-format` must be on your `$PATH`

The plugin can lint and format targets for any Apple platform (iOS, tvOS, watchOS, visionOS) — it runs on the host machine during the build.

## Installation

Add the package to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/HeirloomLogic/SwiftFormatPlugin", from: "1.3.0"),
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

Use [`wearerequired/lint-action`](https://github.com/wearerequired/lint-action) with `swift_format_official` to surface lint violations as inline annotations in pull request diffs. Two modes: lenient (warnings, check passes) and strict (errors, check fails).

### Lenient — warnings only

Violations appear as inline warnings on changed files. The check passes regardless.

```yaml
name: Lint

on:
  pull_request:

permissions:
  checks: write
  contents: read

jobs:
  swift-format-lint:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: wearerequired/lint-action@v2
        with:
          swift_format_official: true
```

### Strict — break the build

Pass `--strict` to fail the check when violations are found. With branch protection enabled, this blocks merges.

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
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: wearerequired/lint-action@v2
        with:
          swift_format_official: true
          swift_format_official_args: "--strict"
```

### Using the plugin's default configuration

If your project does not include its own `.swift-format`, add a step before the lint action to resolve the plugin's curated default:

```yaml
      - name: Resolve swift-format config
        run: |
          if [ ! -f .swift-format ]; then
            swift package resolve
            cp .build/checkouts/SwiftFormatPlugin/.swift-format .swift-format
          fi
```

## Toolchain Compatibility

Match the Swift toolchain on your CI runner to the one on your development machine. Major.minor must align; patch should not matter.

The `swift-format` configuration format has been observed to ship breaking changes without a version bump. A `.swift-format` file that parses cleanly under one Swift minor version may fail under another. If local dev and CI drift, you'll see lint failures that can't be reproduced locally.

## How It Works

On **macOS**, the plugins invoke `swift-format` via `/usr/bin/xcrun`, which resolves to the binary in your active Xcode toolchain. On **Linux**, the plugins invoke `swift-format` directly from your `$PATH`. This means:

- **Zero compile-time cost** — no `swift-syntax` dependency tree to build.
- **Always in sync** with your toolchain's Swift version.
- **No binary artifacts** to download or manage.

## Development

This repo ships a shell script under `bin/` for working on the plugin itself:

| Script | Purpose |
|---|---|
| `bin/regenerate-embedded-fallback` | Rewrites the embedded `fallbackConfigJSON` literal in all plugin source files from the canonical `.swift-format` at the repo root. |

**Editing the default config.** The `.swift-format` file at the repo root is the single source of truth for this plugin's default configuration. If you change it, run `bin/regenerate-embedded-fallback` before committing — the script rewrites the `private let fallbackConfigJSON = """..."""` block in both plugin source files to match.

**Why the duplication exists.** SwiftPM plugin targets cannot share Swift source across targets and cannot carry resources (no `resources:` parameter on `.plugin(...)`, no `PluginContext` API to locate the plugin's own on-disk files), so both plugin source files must embed the fallback as a literal. The generator + CI drift check turns this structural duplication into a managed one: you only ever edit `.swift-format`, and CI fails if the embedded literals are out of sync.

**CI.** `.github/workflows/lint.yml` runs on every pull request and push to `main`. It regenerates the embedded literals and verifies there's no diff (drift check), then runs `swift-format lint` in strict mode on the plugin's own source.

## Links

- [SwiftFormatPlugin repository](https://github.com/HeirloomLogic/SwiftFormatPlugin)
- [`swift-format` repository](https://github.com/swiftlang/swift-format)
- [`swift-format` rules reference](https://github.com/swiftlang/swift-format/blob/main/Documentation/RuleDocumentation.md)

## License

This project is available under the MIT License. See [LICENSE](LICENSE) for details.
