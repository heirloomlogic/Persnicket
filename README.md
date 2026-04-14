# SwiftFormatPlugin

A lightweight SPM plugin that lints and formats Swift source files using the Swift 6 toolchain's `swift-format` command.

Works on **macOS**, **Linux**, and **Windows**.

## Plugins

| Plugin | Type | What it does |
|---|---|---|
| **SwiftFormatBuildToolPlugin** | Build Tool | Runs `swift-format lint` automatically on every build as a pre-build step. |
| **SwiftFormatCommandPlugin** | Command | Runs `swift-format format --in-place` on demand to reformat source files. |

Both plugins work with Swift Package Manager. On macOS, Xcode project integration is also supported.

## Requirements

- **Swift 6.0+** toolchain that includes `swift-format`
- **macOS**: Xcode 16+ (the plugin invokes `swift-format` via `xcrun`)
- **Linux / Windows**: `swift-format` must be on your `$PATH`

## Installation

Add the package to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/HeirloomLogic/SwiftFormatPlugin.git", from: "1.0.0"),
]
```

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

# Linux / Windows
swift-format dump-configuration > .swift-format
```

## Toolchain Compatibility

Match the Swift toolchain on your CI runner to the one on your development machine. Major.minor must align; patch should not matter.

The `swift-format` configuration format has been observed to ship breaking changes without a version bump. A `.swift-format` file that parses cleanly under one Swift minor version may fail under another. If local dev and CI drift, you'll see lint failures that can't be reproduced locally.

## How It Works

On **macOS**, the plugins invoke `swift-format` via `/usr/bin/xcrun`, which resolves to the binary in your active Xcode toolchain. On **Linux** and **Windows**, the plugins invoke `swift-format` directly from your `$PATH`. This means:

- **Zero compile-time cost** — no `swift-syntax` dependency tree to build.
- **Always in sync** with your toolchain's Swift version.
- **No binary artifacts** to download or manage.

## Development

This repo ships a few shell wrappers under `bin/` for working on the plugin itself:

| Script | Purpose |
|---|---|
| `bin/format` | Runs `SwiftFormatCommandPlugin` on this package to format its own sources. |
| `bin/lint` | Fast-path lint via `swift-format` directly (skips SwiftPM). Runs in `--strict` mode. |
| `bin/regenerate-embedded-fallback` | Rewrites the embedded `fallbackConfigJSON` literal in both plugin source files from the canonical `.swift-format` at the repo root. |

**Editing the default config.** The `.swift-format` file at the repo root is the single source of truth for this plugin's default configuration. If you change it, run `bin/regenerate-embedded-fallback` before committing — the script rewrites the `private let fallbackConfigJSON = """..."""` block in both plugin source files to match.

**Why the duplication exists.** SwiftPM plugin targets cannot share Swift source across targets and cannot carry resources (no `resources:` parameter on `.plugin(...)`, no `PluginContext` API to locate the plugin's own on-disk files), so both `SwiftFormatBuildToolPlugin/plugin.swift` and `SwiftFormatCommandPlugin/plugin.swift` must embed the fallback as a literal. The generator + CI drift check turns this structural duplication into a managed one: you only ever edit `.swift-format`, and CI fails if the embedded literals are out of sync.

**CI.** `.github/workflows/lint.yml` runs on every pull request and push to `main`. It regenerates the embedded literals and verifies there's no diff (drift check), then runs `bin/lint` in strict mode.

## Links

- [SwiftFormatPlugin repository](https://github.com/HeirloomLogic/SwiftFormatPlugin)
- [`swift-format` repository](https://github.com/swiftlang/swift-format)
- [`swift-format` rules reference](https://github.com/swiftlang/swift-format/blob/main/Documentation/RuleDocumentation.md)

## License

This project is available under the MIT License. See [LICENSE](LICENSE) for details.
