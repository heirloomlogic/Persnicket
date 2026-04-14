# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-04-14

### Changed

- Warn and continue (instead of failing the build) when `swift-format` cannot parse the configuration file.

### Added

- CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md, issue templates, and PR template.

## [1.2.0] - 2026-04-13

### Added

- Shared `.swift-format` configuration file as the single source of truth for the default config.
- CI workflow (`.github/workflows/lint.yml`) with embedded-fallback drift check and strict lint.
- Development scripts: `bin/format`, `bin/lint`, `bin/regenerate-embedded-fallback`.

## [1.1.0] - 2026-02-19

### Fixed

- Use `path` instead of `absoluteString` for file URLs in `SwiftFormatCommandPlugin`, fixing path encoding issues.

## [1.0.0] - 2026-02-09

### Added

- `SwiftFormatBuildToolPlugin` — runs `swift-format lint` as a pre-build step.
- `SwiftFormatCommandPlugin` — runs `swift-format format --in-place` on demand.
- Xcode project integration for both plugins (macOS).
- Embedded fallback configuration for projects without a `.swift-format` file.

[1.3.0]: https://github.com/HeirloomLogic/SwiftFormatPlugin/compare/1.2.0...1.3.0
[1.2.0]: https://github.com/HeirloomLogic/SwiftFormatPlugin/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/HeirloomLogic/SwiftFormatPlugin/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/HeirloomLogic/SwiftFormatPlugin/releases/tag/1.0.0
