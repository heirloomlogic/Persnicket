# Contributing to SwiftFormatPlugin

## Requirements

The plugin supports Swift 6.0+ / Xcode 16+ for end users. To contribute, you need:

- Swift 6.3+ toolchain with `swift-format`
- macOS: Xcode 26.3+
- Linux: `swift-format` on your `$PATH`

## Development workflow

This repo includes shell scripts under `bin/` for working on the plugin:

| Script | Purpose |
|---|---|
| `bin/format` | Reformats the plugin's own sources via `SwiftFormatCommandPlugin`. |
| `bin/lint` | Runs `swift-format lint --strict` directly (fast, skips SwiftPM). |
| `bin/regenerate-embedded-fallback` | Rewrites the embedded `fallbackConfigJSON` literals in both plugin source files from `.swift-format`. |

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
3. Run `bin/lint` and confirm it passes.
4. If you changed `.swift-format` or anything related to the fallback config, run `bin/regenerate-embedded-fallback`.
5. Open a pull request against `main`.

Keep PRs focused — one logical change per PR.

## CI checks

The GitHub Actions workflow (`.github/workflows/lint.yml`) runs on every PR and push to `main`:

1. Regenerates the embedded fallback literals and verifies there is no diff.
2. Runs `bin/lint` in strict mode.

Both checks must pass before merge.

## Reporting issues

Use the [issue templates](https://github.com/HeirloomLogic/SwiftFormatPlugin/issues/new/choose) to report bugs or request features.

## Code of Conduct

This project follows the [Contributor Covenant v2.1](.github/CODE_OF_CONDUCT.md). Please read it before participating.
