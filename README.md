<p align="center">
  <img src=".github/Persnicket-logo@2x.png" alt="Persnicket" height="256">
</p>

# Persnicket

A lightweight SPM plugin that lints and formats Swift source files. Its only dependency is the Swift toolchain's built-in `swift-format` binary.

[![Swift 6.0+](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20|%20Linux-blue.svg)](https://swift.org)
[![CI](https://github.com/HeirloomLogic/Persnicket/actions/workflows/lint.yml/badge.svg)](https://github.com/HeirloomLogic/Persnicket/actions/workflows/lint.yml)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Plugins

| Plugin | Type | What it does |
|---|---|---|
| **Persnoop** | Build Tool | Runs `swift-format lint` automatically on every build as a pre-build step. Violations appear as build warnings. |
| **Persnipe** | Command | Runs `swift-format format --in-place` on demand to reformat source files. |

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
    .package(url: "https://github.com/HeirloomLogic/Persnicket", from: "2.0.0"),
]
```

Or in Xcode: **File → Add Package Dependencies** and enter the repository URL.

### Build Tool Plugin (automatic linting)

Apply the plugin to any target you want linted on every build:

```swift
.target(
    name: "MyTarget",
    plugins: [
        .plugin(name: "Persnoop", package: "Persnicket"),
    ]
)
```

Lint violations are reported as **build warnings** — they show up inline in Xcode and in `swift build` output, but they do not fail the build. (`swift-format lint` only exits non-zero in `--strict` mode, and a failing pre-build step would block compilation entirely.) If you want violations to *fail* a build, run `swift-format lint --strict` directly in CI — see [CI](#ci) below.

If your package is itself consumed as a dependency, applying Persnoop pulls Persnicket into your consumers' dependency graph too. See [DEV-TOOLING.md](DEV-TOOLING.md) to gate it out so only your own builds run the linter.

### Command Plugin (on-demand formatting)

The command plugin registers the SwiftPM built-in `format-source-code` verb. Run it from the command line:

```bash
swift package plugin --allow-writing-to-package-directory format-source-code
```

The plugin runs silently on success — use `git diff` to see what changed.

To format only specific targets, pass `--target` (repeatable):

```bash
swift package plugin --allow-writing-to-package-directory format-source-code --target MyTarget
```

In Xcode: **right-click your project or package → Persnipe**.

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

For CI lint workflows we recommend invoking `swift-format lint --strict` directly and registering a GitHub [problem matcher](https://github.com/actions/toolkit/blob/main/docs/problem-matchers.md) so violations appear as inline annotations on the pull request diff. The matcher is a small regex file that tells the runner to parse `swift-format`'s output (`path:line:col: severity: message`) into native annotations — no third-party action, no extra permissions, and the linter's exit code drives job pass/fail directly.

A ready-to-use matcher ships in this repo at [`.github/swift-format-matcher.json`](.github/swift-format-matcher.json), along with a `bin/ci-lint-setup` script that wires everything up in a single step. The script:

- copies the default [`.swift-format`](.swift-format) into your project root if you don't already have one,
- installs the problem matcher at `.github/swift-format-matcher.json`, and
- emits the `::add-matcher::` workflow command so violations appear as inline PR annotations.

It's idempotent and never overwrites an existing project `.swift-format`. Sample workflow (macOS):

```yaml
name: Lint

on:
  pull_request:
  push:
    branches: [main]

jobs:
  swift-format-lint:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - name: Setup swift-format lint
        run: |
          swift package resolve
          .build/checkouts/Persnicket/bin/ci-lint-setup

      - name: Lint (strict)
        run: xcrun swift-format lint --strict --parallel --recursive --configuration .swift-format Sources Tests
```

On Linux, install Swift with `swift-actions/setup-swift@v2` before the setup step, and drop the `xcrun` prefix from the lint command. The setup script itself is portable `sh` and runs unchanged.

**Caveats:**

- Inline annotations on the PR "Files changed" tab only show for lines that are part of the diff. Violations on unchanged lines still appear in the workflow run summary.
- GitHub caps workflow-command annotations at 10 errors and 10 warnings shown inline per run; the remainder are listed in the run summary. For typical PRs this is fine — for a first-time lint sweep across a large codebase, run `swift-format lint` locally for the full list.
- `ci-lint-setup` refreshes `.github/swift-format-matcher.json` from this package on every run. If you've customized that file, your changes will be overwritten — rename your copy and register it with your own `::add-matcher::` command instead.

## Toolchain Compatibility

Match the Swift toolchain on your CI runner to the one on your development machine. Major.minor must align; patch should not matter.

The `swift-format` configuration format has previously shipped breaking changes without a version bump. A `.swift-format` file that parses cleanly under one Swift minor version may fail under another. If local dev and CI drift, you could see lint failures that can't be reproduced locally.

When the plugin detects that the active toolchain's `swift-format` cannot parse the configuration, it emits a warning and **skips linting rather than failing the build**. Keep an eye out for the `linting skipped` warning — a passing build does not guarantee the linter actually ran.

When using `swift-actions/setup-swift@v2` on Linux, the action may install an older default Swift if `swift-version` is omitted. This can produce a `swift-format cannot parse the configuration — linting skipped` warning, although the build succeeds. Pin the version to match your project:

```yaml
- uses: swift-actions/setup-swift@v2
  with:
    swift-version: "6.2"
```

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

**Formatting the plugin's own source.** The `Persnipe` command plugin only formats its host package's source modules, so it's a no-op when invoked on Persnicket itself (this package contains only plugin targets). To reformat the plugin sources after editing them or changing `.swift-format`, invoke `swift-format` directly:

```sh
xcrun swift-format format --in-place --parallel --recursive --configuration .swift-format Plugins/
```

**Why the duplication exists.** SwiftPM plugin targets cannot share Swift source across targets and cannot carry resources (no `resources:` parameter on `.plugin(...)`, no `PluginContext` API to locate the plugin's own on-disk files), so both plugin source files must embed the fallback as a literal. The generator + CI drift check turns this structural duplication into a managed one: you only ever edit `.swift-format`, and CI fails if the embedded literals are out of sync.

**CI.** `.github/workflows/lint.yml` runs on every pull request and push to `main`. It regenerates the embedded literals and verifies there's no diff (drift check), verifies the shared plugin infrastructure is byte-identical across both targets, then runs `swift-format lint` in strict mode on the plugin's own source.

## Links

- [Persnicket repository](https://github.com/HeirloomLogic/Persnicket)
- [Keeping dev-only plugins out of consumers' dependency graphs](DEV-TOOLING.md)
- [`swift-format` repository](https://github.com/swiftlang/swift-format)
- [`swift-format` rules reference](https://github.com/swiftlang/swift-format/blob/main/Documentation/RuleDocumentation.md)

## License

This project is available under the MIT License. See [LICENSE](LICENSE) for details.
