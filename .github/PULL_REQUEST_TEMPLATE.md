## What

<!-- Brief description of the change. -->

## Why

<!-- Motivation or linked issue. -->

## Checklist

- [ ] `xcrun swift-format lint --strict --parallel --recursive --configuration .swift-format Plugins/` passes locally
- [ ] `bin/regenerate-embedded-fallback` run (if `.swift-format` or fallback logic changed)
- [ ] No unrelated changes included
