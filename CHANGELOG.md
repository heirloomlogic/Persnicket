# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- CI now covers symlinked source files, JSON5 configuration files, unusable configurations, Persnipe failures, target argument validation, and the advertised Swift 6.0 floor.
- `ci-lint-setup` now installs separate problem matchers for file diagnostics and configuration diagnostics.

### Changed

- Persnipe accepts `--target <name>` and `--target=<name>`, rejects missing values, removes duplicate target names, and continues with later targets after one target fails before returning a failure.
- On macOS, the plugins select `swift-format` from the toolchain running the build. Probe-cache keys now include toolchain environment variables and the resolved executable, so toolchain changes invalidate prior results.
- CI runs only for pull request events, applies job timeouts, avoids persisting checkout credentials, and runs Linux checks in versioned Swift containers. The published workflow guidance matches these safeguards.
- Development-tooling guidance now tells package authors to commit `Package.resolved` and use `swift package resolve --force-resolved-versions` before running scripts from a dependency checkout.

### Fixed

- Configuration validation now accepts the JSON5 syntax supported by `swift-format` in Swift 6.2 and later while still rejecting malformed or non-object configuration files.
- The plugins pass `--follow-symlinks`, allowing Swift 6.2 and later to lint and format source files reached through symlinks.
- Persnipe no longer reports success when `swift-format` rejects a configuration or fails for a target.
- GitHub Actions annotations now distinguish configuration diagnostics from source-file diagnostics.

## [2.2.0] - 2026-07-03

### Added

- Persnoop caches successful preflight probes per target and invalidates the cache when the configuration or resolved toolchain changes.
- The Xcode Persnipe command supports repeatable `--target <name>` arguments and rejects unknown arguments, matching the SwiftPM command.
- CI type-checks the Xcode plugin variants, exercises the Swift 6.0 minimum, and verifies plugin outcomes on macOS and Linux.

### Changed

- An absolute executable path in `SWIFT_FORMAT` takes precedence on every platform, including macOS.
- GitHub Actions dependencies are pinned and managed through Dependabot; `actions/checkout` was updated to 7.0.0.

### Fixed

- Persnoop strict mode fails the build when `swift-format` is missing or cannot use the configuration instead of warning and skipping linting.
- Missing executables receive their own diagnostic instead of being reported as configuration mismatches.
- Linux discovery rejects relative overrides and directories, and follows a symlinked `swift` executable to find the matching `swift-format` binary.
- Persnipe skips targets without source files instead of invoking `swift-format` with no paths.
- `bin/regenerate-embedded-fallback` rejects CRLF configurations and missing literal delimiters, and preserves file permissions when rewriting plugin sources.

## [2.1.0] - 2026-06-20

### Added

- Persnoop has an opt-in strict mode. Set `PERSNICKET_STRICT` to `1`, `true`, or `yes`, or add a `.persnicket-strict` file at the project root, to make lint violations fail the build.
- Linux CI compile-checks the plugins through the `Examples/CompileCheck` consumer fixture.

### Changed

- Xcode plugin variants process each target's Swift source files instead of recursively processing the project directory.
- Persnipe supports repeatable `--target <name>` arguments and rejects unknown arguments.
- Persnoop ignores non-source target files, matching Persnipe.
- The CI workflow restricts `GITHUB_TOKEN` to read-only repository contents.

### Fixed

- `bin/regenerate-embedded-fallback` refuses configurations containing a backslash or triple-quote sequence that would corrupt the generated Swift literal.
- Documentation now describes Persnoop's default warning-only behavior, configuration and toolchain mismatch handling, and problem-matcher replacement by `ci-lint-setup`.

## [2.0.2] - 2026-06-10

### Added

- `DEV-TOOLING.md` documents how package authors can keep Persnicket and other development-only build-tool plugins out of downstream dependency graphs with a gitignored `.dev-tooling` sentinel.

## [2.0.1] - 2026-05-28

### Changed

- README updates and refreshed logo asset.

## [2.0.0] - 2026-05-11

### Changed (breaking)

- Rename the package from `SwiftFormatPlugin` to `Persnicket`.
- Rename the build-tool plugin from `SwiftFormatBuildToolPlugin` to `Persnoop`.
- Rename the command plugin from `SwiftFormatCommandPlugin` to `Persnipe`.

Consumers must update `Package.swift`:

```swift
.package(url: "https://github.com/HeirloomLogic/Persnicket", from: "2.0.0"),
// and
.plugin(name: "Persnoop", package: "Persnicket"),
.plugin(name: "Persnipe", package: "Persnicket"),
```

### Added

- `bin/ci-lint-setup` consolidates downstream CI plumbing (default `.swift-format`, problem matcher install, `::add-matcher::`) into one step; recommended workflow drops to checkout → setup → lint.

## [1.6.2] - 2026-05-11

### Changed

- Replace `lint-action` with a GitHub problem matcher for PR annotations.

## [1.6.1] - 2026-05-09

### Fixed

- Stop preflight probe from leaking into target sources.

## [1.6.0] - 2026-05-08

### Added

- Linux `swift-format` auto-discovery with documented alternatives.

### Changed

- Document `swift-version` pin for `swift-actions/setup-swift@v2` on Linux.

### Fixed

- Pass launcher to shared methods in Xcode plugin extensions.

## [1.5.0] - 2026-05-02

### Added

- CI documentation covering `swift-format` lint integration.

### Changed

- Consolidate CI workflow examples in the README; add a toolchain link.
- Remove `bin/lint` and `bin/format` shell scripts; CI now uses `swift-format lint` directly.

## [1.4.0] - 2026-05-01

### Changed

- Update `.swift-format` options and sync the embedded fallback.
- README: restore requirements info, add CI badge, fix heading hierarchy, clarify platform scope.

### Fixed

- Fix command plugin exiting 0 when `swift-format` fails (now throws so CI catches failures).
- Fix Xcode command plugin dropping stderr content from non-config error messages.
- Fix broken `CODE_OF_CONDUCT.md` link in `CONTRIBUTING.md` after file was moved to `.github/`.
- Fix inconsistent use of deprecated `.path` vs `.path(percentEncoded: false)` across plugins.
- Improve preflight probe to warn (instead of silently succeeding) when it cannot execute.
- Add pattern-match verification to `bin/regenerate-embedded-fallback`.

## [1.3.0] - 2026-04-15

### Changed

- Warn and continue (instead of failing the build) when `swift-format` cannot parse the configuration file.

### Added

- CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md, issue templates, and PR template.

## [1.2.0] - 2026-04-13

### Added

- Shared `.swift-format` configuration file as the single source of truth for the default config.
- CI workflow (`.github/workflows/lint.yml`) with embedded-fallback drift check and strict lint.
- Development script: `bin/regenerate-embedded-fallback`.

## [1.1.0] - 2026-02-19

### Fixed

- Use `path` instead of `absoluteString` for file URLs in `SwiftFormatCommandPlugin`, fixing path encoding issues.

## [1.0.0] - 2026-02-08

### Added

- `SwiftFormatBuildToolPlugin` — runs `swift-format lint` as a pre-build step.
- `SwiftFormatCommandPlugin` — runs `swift-format format --in-place` on demand.
- Xcode project integration for both plugins (macOS).
- Embedded fallback configuration for projects without a `.swift-format` file.

[Unreleased]: https://github.com/HeirloomLogic/Persnicket/compare/2.2.0...HEAD
[2.2.0]: https://github.com/HeirloomLogic/Persnicket/compare/2.1.0...2.2.0
[2.1.0]: https://github.com/HeirloomLogic/Persnicket/compare/2.0.2...2.1.0
[2.0.2]: https://github.com/HeirloomLogic/Persnicket/compare/2.0.1...2.0.2
[2.0.1]: https://github.com/HeirloomLogic/Persnicket/compare/2.0.0...2.0.1
[2.0.0]: https://github.com/HeirloomLogic/Persnicket/compare/1.6.2...2.0.0
[1.6.2]: https://github.com/HeirloomLogic/Persnicket/compare/1.6.1...1.6.2
[1.6.1]: https://github.com/HeirloomLogic/Persnicket/compare/1.6.0...1.6.1
[1.6.0]: https://github.com/HeirloomLogic/Persnicket/compare/1.5.0...1.6.0
[1.5.0]: https://github.com/HeirloomLogic/Persnicket/compare/1.4.0...1.5.0
[1.4.0]: https://github.com/HeirloomLogic/Persnicket/compare/1.3.0...1.4.0
[1.3.0]: https://github.com/HeirloomLogic/Persnicket/compare/1.2.0...1.3.0
[1.2.0]: https://github.com/HeirloomLogic/Persnicket/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/HeirloomLogic/Persnicket/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/HeirloomLogic/Persnicket/releases/tag/1.0.0
