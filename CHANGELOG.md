# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Xcode plugin variants now lint/format each target's own Swift source files instead of recursively
  processing the entire project directory. This stops Persnipe from rewriting vendored or generated
  Swift code the project doesn't own, and stops Persnoop from re-linting the whole project once per
  attached target.
- `Persnipe` now supports `--target <name>` (repeatable) to limit formatting to specific targets,
  and rejects unrecognized arguments instead of silently ignoring them.
- `Persnoop` now filters target files to `.source` type, matching `Persnipe`'s behavior.

### Added

- `Persnoop` gained an opt-in **strict mode**: set the `PERSNICKET_STRICT` environment variable
  (`1`/`true`/`yes`) or create a `.persnicket-strict` file in the project root, and Persnoop passes
  `--strict` to `swift-format lint` so violations fail the build. Off by default — the plugin
  remains warnings-only unless you opt in.
- CI: the Linux job now compile-checks the plugins via the `Examples/CompileCheck` fixture, so the
  Linux-only discovery code paths are built on every PR.
- CI: workflow `GITHUB_TOKEN` restricted to `contents: read`.
- `bin/regenerate-embedded-fallback` refuses to run if `.swift-format` contains a backslash or
  `"""`, either of which would silently corrupt the embedded Swift string literal.

### Fixed

- README documents that Persnoop reports violations as build warnings (it never fails the build),
  that linting is skipped with a warning on config/toolchain mismatch, and that `ci-lint-setup`
  overwrites the installed problem matcher.
- CHANGELOG version links.

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

[Unreleased]: https://github.com/HeirloomLogic/Persnicket/compare/2.0.1...HEAD
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
