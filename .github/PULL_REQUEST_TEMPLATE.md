## What

<!-- Brief description of the change. -->

## Why

<!-- Motivation or linked issue. -->

## Checklist

- [ ] `xcrun swift-format lint --strict --parallel --recursive --configuration .swift-format Plugins/ Examples/ Package.swift` passes locally
- [ ] `bin/regenerate-embedded-fallback` run (if `.swift-format` or fallback logic changed)
- [ ] `bin/check-shared-plugin-code` passes (if either plugin's shared infrastructure changed)
- [ ] No unrelated changes included
