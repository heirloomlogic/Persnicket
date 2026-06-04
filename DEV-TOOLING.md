# Keeping dev-only plugins out of your consumers' dependency graph

Persnoop is dev-only tooling — it lints *your* source on every build. But applying it adds **Persnicket** to your `Package.swift` `dependencies:` and attaches a build-tool plugin to your targets. If your package is itself consumed as a dependency, that leaks downstream: every consumer must resolve, fetch, and trust Persnicket just to build your target, even though the linter is irrelevant to them. The same applies to any dev-only build-tool plugin you attach to a target — for example [SwiftLintPlugins](https://github.com/SimplyDanny/SwiftLintPlugins).

SwiftPM has no first-class concept of a dev-only dependency, so there is no built-in flag for this. This guide gates the tooling on a gitignored **`.dev-tooling`** sentinel file: a filesystem feature-flag present only in your own working clone and in CI. When it is absent — as it always is for consumers — the dependency and plugin drop out of the manifest entirely.

> This recipe applies to packages that **both** use Persnoop **and** are consumed as a dependency by other packages. If your package is a leaf (an app, or a tool nobody depends on), there is nothing downstream to leak into — apply Persnoop normally as shown in the [README](README.md#build-tool-plugin-automatic-linting).

## Recipe

### 1. Detect the sentinel in `Package.swift`

Add `import Foundation` and, before the `let package = Package(...)` declaration, test for the sentinel. Anchor the lookup to the manifest's own directory with `#filePath` rather than the current working directory, so it resolves the same way regardless of where the build is invoked from:

```swift
// swift-tools-version: 6.0

import PackageDescription
import Foundation

// Dev-only tooling (swift-format linting) must not leak into downstream consumers'
// dependency graphs. SwiftPM has no first-class dev-dependencies, so gate it on a
// gitignored `.dev-tooling` sentinel, present only in this package's own working
// clone (and created as a step in CI). `#filePath` anchors the lookup to this
// manifest's directory, independent of the current working directory.
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let isDevBuild = FileManager.default.fileExists(
    atPath: packageDir.appendingPathComponent(".dev-tooling").path)
```

### 2. Gate the dependency

Move the Persnicket dependency into a conditional array that is empty unless the sentinel is present:

```swift
let devDependencies: [Package.Dependency] = isDevBuild
    ? [.package(url: "https://github.com/HeirloomLogic/Persnicket", from: "2.0.0")]
    : []
```

### 3. Gate the plugin and apply it to your targets

Do the same for the plugin usage, then attach it to each target you want linted:

```swift
let devPlugins: [Target.PluginUsage] = isDevBuild
    ? [.plugin(name: "Persnoop", package: "Persnicket")]
    : []

let package = Package(
    name: "MyLibrary",
    dependencies: devDependencies,
    targets: [
        .target(
            name: "MyLibrary",
            plugins: devPlugins
        ),
        .testTarget(
            name: "MyLibraryTests",
            dependencies: ["MyLibrary"],
            plugins: devPlugins
        ),
    ]
)
```

A second dev-only build-tool plugin slots into the same two arrays — add its `.package(...)` to `devDependencies` and its `.plugin(...)` to `devPlugins`. For example, SwiftLintPlugins is gated identically.

### 4. Gitignore the sentinel

Add it to your `.gitignore` so it never reaches consumers:

```
.dev-tooling
```

### 5. Turn tooling on locally and in CI

The sentinel is created on demand — it is the explicit signal that you are doing dev work. Create it once after cloning:

```bash
touch .dev-tooling
```

In CI, create it before resolving the package, so the lint step sees the plugin:

```yaml
- name: Setup swift-format lint
  run: |
    touch .dev-tooling
    swift package resolve
    .build/checkouts/Persnicket/bin/ci-lint-setup
```

**Caveats:**

- SwiftPM caches the *evaluated* manifest keyed on `Package.swift`'s **text**, not on external files. Toggling `.dev-tooling` after a build is invisible to that cache — you keep whichever mode was evaluated first. To switch modes, run `swift package purge-cache` then `swift package resolve`. In Xcode, quit, run `swift package purge-cache`, then reopen the package. Note that `swift package reset` and Xcode's "Reset Package Caches" do **not** clear this particular layer.
- A fresh clone that runs `touch .dev-tooling` *before* its first build never hits this — the cache is populated in dev mode from the start.
