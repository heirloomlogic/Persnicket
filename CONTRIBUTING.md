# Contributing to Persnicket

## Requirements

The plugin supports Swift 6.0+ / Xcode 16+ for end users. To contribute, you need:

- Swift 6.3+ toolchain with `swift-format`
- macOS: Xcode 26.3+
- Linux: `swift-format` on your `$PATH`

## Development workflow

This repo includes shell scripts under `bin/` for working on the plugin:

| Script | Purpose |
|---|---|
| `bin/regenerate-embedded-fallback` | Rewrites the embedded `fallbackConfigJSON` literals in all plugin source files from `.swift-format`. |
| `bin/check-shared-plugin-code` | Verifies that the shared plugin infrastructure section is byte-identical across both plugin targets. |

### The `.swift-format` single-source-of-truth rule

The `.swift-format` file at the repo root is the canonical configuration. Both plugin targets embed a copy of this config as a string literal (`fallbackConfigJSON`) because SwiftPM plugin targets cannot share source files or carry resources.

**Never edit the `fallbackConfigJSON` literals by hand.** Edit `.swift-format`, then run:

```bash
bin/regenerate-embedded-fallback
```

CI will reject your PR if the embedded literals drift from `.swift-format`.

## Submitting changes

1. Fork the repository and create a branch from `main`.
2. Make your changes.
3. Run `xcrun swift-format lint --strict --parallel --recursive --configuration .swift-format Plugins/ Examples/ Package.swift` and confirm it passes.
4. If you changed `.swift-format` or anything related to the fallback config, run `bin/regenerate-embedded-fallback`. If you changed the shared plugin infrastructure, mirror it into the other plugin and run `bin/check-shared-plugin-code`.
5. Open a pull request against `main`.

Keep PRs focused — one logical change per PR.

## CI checks

The GitHub Actions workflow (`.github/workflows/lint.yml`) runs on every pull request, in three jobs.

**macOS** (`swift-format (strict)`):

1. Regenerates the embedded fallback literals and verifies there is no diff.
2. Verifies the shared plugin infrastructure is identical across both plugin targets.
3. Typechecks the `#if canImport(XcodeProjectPlugin)` Xcode plugin variants against Xcode's PluginAPI — `swift build` never compiles them, so this is their only verification.
4. Runs `swift-format lint --strict` over `Plugins/`, `Examples/`, and `Package.swift`.
5. Builds the `Examples/CompileCheck` consumer fixture and runs Persnipe over it, asserting that Persnipe reformats a misformatted file, batches every requested target into one swift-format invocation and names those targets when it fails, that `--target` scoping works, that a symlinked source file is formatted through the link, and that a configuration swift-format rejects fails the command.
6. Verifies Persnoop shows non-strict findings in `swift build`, skips unchanged lint work, reruns for source changes, configuration edits/removal/addition, and formatter replacement at the same path, and reruns unchanged strict failures. The same fixture generates a 4,102-file target and verifies both plugins split it into bounded invocations without missing or duplicating a path.
7. Verifies Persnoop's strict mode fails the build on a lint violation, and that the failure is the expected violation.
8. Verifies an unusable `.swift-format` fails the build, and a commented (JSON5) one builds.

**Linux** (`swift:6.2` container) repeats steps 4–8 — covering the `#if !os(macOS)` discovery code paths — and also verifies that misconfigured `$SWIFT_FORMAT` overrides warn and fall back to discovery.

**Swift 6.0 floor** (`swift:6.0.0` container, the advertised minimum) builds the fixture and runs Persnipe, verifies Persnoop's visible incremental lint behavior and both plugins' large-target chunking, then verifies that strict mode fails on a violation, that strict mode reports rules swift-format 600 doesn't know instead of failing cryptically, that Persnipe fails on a rejected configuration, and that an unusable `.swift-format` fails the build.

Run `PERSNICKET_TEST_BUILD_SYSTEM=native Examples/CompileCheck/verify-large-target.sh` to test native SwiftPM explicitly, or set the variable to `swiftbuild` when the installed toolchain supports it. A failed fixture preserves its scratch directory and prints the log tails.

Run `Examples/CompileCheck/verify-configuration.sh` to exercise root and nested configurations, config additions/edits/removals, skip/resume, repeated strict failures, explicit fallback, and symlink destination configs on supported formatters. It accepts the same `PERSNICKET_TEST_BUILD_SYSTEM` selection and runs in all three CI jobs.

All checks must pass before merge.

## Release notes

Publish release notes in [GitHub Releases](https://github.com/HeirloomLogic/Persnicket/releases). `CHANGELOG.md` is a historical archive through 2.2.0 and does not need an entry or version update for new releases. Review the changes since the previous tag when preparing each release.

## Reporting issues

Use the [issue templates](https://github.com/HeirloomLogic/Persnicket/issues/new/choose) to report bugs or request features.

## Code of Conduct

This project follows the [Contributor Covenant v2.1](.github/CODE_OF_CONDUCT.md). Please read it before participating.
