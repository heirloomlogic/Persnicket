import Foundation
import PackagePlugin

@main
struct Persnoop: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        guard let sourceModule = target as? SourceModuleTarget else {
            Diagnostics.remark(
                "Skipping target \"\(target.name)\" because it is not a source module."
            )
            return []
        }

        let sourceFiles = sourceModule.sourceFiles(withSuffix: ".swift").filter {
            $0.type == .source && $0.url.pathExtension == "swift"
        }
        guard !sourceFiles.isEmpty else {
            Diagnostics.remark(
                "Skipping target \"\(target.name)\" because it has no Swift source files."
            )
            return []
        }

        pinDeveloperDirectory(toXcodeOf: try? context.tool(named: "swift-format").url)
        return try lintCommands(
            targetName: target.name,
            sourceFiles: sourceFiles.map(\.url),
            projectRoot: context.package.directoryURL,
            pluginWorkDirectory: context.pluginWorkDirectoryURL
        )
    }

    /// Builds the prebuild lint command for one target, shared by the SwiftPM and
    /// Xcode entry points. Returns no commands — after a diagnostic — when linting
    /// can't run: toolchain and config trouble warns and skips, or fails the build in
    /// strict mode; an unusable config file is always an error.
    func lintCommands(
        targetName: String,
        sourceFiles: [URL],
        projectRoot: URL,
        pluginWorkDirectory: URL
    ) throws -> [Command] {
        let strict = strictModeEnabled(projectRoot: projectRoot)

        guard let launcher = swiftFormatLauncher() else {
            let message = swiftFormatNotFoundMessage(
                outcome: strict ? "failing the build (strict mode)" : "linting skipped"
            )
            if strict {
                Diagnostics.error(message)
            } else {
                Diagnostics.warning(message)
            }
            return []
        }

        guard
            let configPath = try resolveConfiguration(
                launcher: launcher,
                projectRoot: projectRoot,
                pluginWorkDirectory: pluginWorkDirectory
            )
        else {
            return []
        }

        let probe = probeSwiftFormat(
            launcher: launcher,
            configPath: configPath,
            strict: strict,
            pluginWorkDirectory: pluginWorkDirectory
        )
        guard case .ok = probe else {
            emitProbeFailure(probe, launcher: launcher, configPath: configPath, strict: strict)
            return []
        }

        var arguments =
            launcher.leadingArguments + ["lint"] + commonSwiftFormatOptions + [
                "--configuration", configPath,
            ]
        if strict {
            arguments.append("--strict")
        }
        arguments += sourceFiles.map { $0.path(percentEncoded: false) }

        let outputsDir = pluginWorkDirectory.appendingPathComponent(
            "outputs",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputsDir,
            withIntermediateDirectories: true
        )

        return [
            .prebuildCommand(
                displayName: "swift-format lint (\(targetName))",
                executable: launcher.executable,
                arguments: arguments,
                environment: toolchainSelectionEnvironment(),
                outputFilesDirectory: outputsDir
            )
        ]
    }

    // MARK: - Shared Plugin Infrastructure (must be identical across all plugin targets)
    //
    // Some members are used by only one plugin (`logSwiftFormatVersion` only by
    // Persnipe; `strictModeEnabled`, the probe, and `toolchainSelectionEnvironment`
    // only by Persnoop) but live here so the section stays byte-identical across both
    // targets — the accepted cost of SwiftPM's no-shared-plugin-source rule.

    /// Resolves how to invoke `swift-format` on the current platform.
    ///
    /// On every platform, an absolute, executable `$SWIFT_FORMAT` takes precedence —
    /// the escape hatch for custom toolchains or non-standard layouts.
    ///
    /// **macOS:** otherwise dispatches through `/usr/bin/xcrun` so the binary tracks
    /// the active Xcode toolchain.
    ///
    /// **Linux:** otherwise auto-discovers the toolchain's `swift-format` so downstream
    /// consumers don't have to symlink it into `/usr/local/bin` from CI. See
    /// `resolveLinuxSwiftFormatPath` for the search order.
    ///
    /// Returns nil when Linux discovery fails. The caller reports
    /// `swiftFormatNotFoundMessage` at the severity its own contract calls for:
    /// Persnoop warns and skips (or fails in strict mode), Persnipe fails.
    func swiftFormatLauncher() -> SwiftFormatLauncher? {
        if let override = swiftFormatOverridePath() {
            return SwiftFormatLauncher(
                executable: URL(fileURLWithPath: override),
                leadingArguments: []
            )
        }
        #if os(macOS)
        return SwiftFormatLauncher(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            leadingArguments: ["swift-format"]
        )
        #else
        guard let resolved = resolveLinuxSwiftFormatPath() else {
            return nil
        }
        return SwiftFormatLauncher(
            executable: URL(fileURLWithPath: resolved),
            leadingArguments: []
        )
        #endif
    }

    /// Explains a failed Linux discovery; `outcome` says what the plugin does about it.
    func swiftFormatNotFoundMessage(outcome: String) -> String {
        """
        swift-format binary not found — \(outcome).

        Searched (in order):
          1. $SWIFT_FORMAT environment variable
          2. Sibling of `swift` on $PATH (canonical Swift toolchain location)
          3. /usr/local/bin/swift-format
          4. /usr/bin/swift-format
          5. swift-format on $PATH

        Most Linux Swift toolchains ship swift-format in the same directory as `swift`. \
        If your setup differs, set the SWIFT_FORMAT environment variable to an absolute path. \
        See https://github.com/HeirloomLogic/Persnicket#how-it-works
        """
    }

    /// Returns the `$SWIFT_FORMAT` override — an absolute path to a `swift-format`
    /// binary — honored on **every** platform, including macOS where it takes
    /// precedence over `xcrun swift-format`. Returns nil when it is unset or empty,
    /// not absolute, or not an executable regular file; in the latter two cases it
    /// warns and lets the caller fall through to the platform default.
    private func swiftFormatOverridePath() -> String? {
        guard let override = ProcessInfo.processInfo.environment["SWIFT_FORMAT"],
            !override.isEmpty
        else {
            return nil
        }
        if !override.hasPrefix("/") {
            Diagnostics.warning(
                """
                $SWIFT_FORMAT is set to "\(override)", which is not an absolute path — \
                ignoring it and falling back to the default toolchain swift-format. Set it \
                to an absolute path such as /usr/bin/swift-format.
                """
            )
            return nil
        }
        if isExecutableRegularFile(override) {
            return override
        }
        Diagnostics.warning(
            """
            $SWIFT_FORMAT is set to "\(override)" but it is not an executable file. \
            Falling back to the default toolchain swift-format.
            """
        )
        return nil
    }

    /// Whether `path` is an executable *regular file*. `FileManager.isExecutableFile`
    /// alone returns `true` for searchable directories (access(2) `X_OK`), so a
    /// directory named `swift-format` would otherwise pass discovery.
    private func isExecutableRegularFile(_ path: String) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        return fm.isExecutableFile(atPath: path)
            && fm.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    #if !os(macOS)
    /// Walks the Linux discovery chain and returns the first executable swift-format
    /// it finds, or nil if no candidate exists. The `$SWIFT_FORMAT` override is applied
    /// earlier by `swiftFormatOverridePath`, so it is not repeated here.
    private func resolveLinuxSwiftFormatPath() -> String? {
        let env = ProcessInfo.processInfo.environment

        if let swiftDir = directoryContainingExecutable(named: "swift", env: env) {
            let sibling = swiftDir + "/swift-format"
            if isExecutableRegularFile(sibling) {
                return sibling
            }
            // `swift` on $PATH may be a symlink (e.g. update-alternatives) whose
            // target lives in the real toolchain bin/ next to swift-format.
            let resolvedDir = URL(fileURLWithPath: swiftDir + "/swift")
                .resolvingSymlinksInPath()
                .deletingLastPathComponent()
                .path
            let resolvedSibling = resolvedDir + "/swift-format"
            if resolvedDir != swiftDir, isExecutableRegularFile(resolvedSibling) {
                return resolvedSibling
            }
        }

        for candidate in ["/usr/local/bin/swift-format", "/usr/bin/swift-format"]
        where isExecutableRegularFile(candidate) {
            return candidate
        }

        if let dir = directoryContainingExecutable(named: "swift-format", env: env) {
            return dir + "/swift-format"
        }

        return nil
    }

    /// Returns the first directory in `$PATH` containing an executable named `name`.
    private func directoryContainingExecutable(named name: String, env: [String: String]) -> String? {
        guard let pathVar = env["PATH"], !pathVar.isEmpty else { return nil }
        for component in pathVar.split(separator: ":", omittingEmptySubsequences: true) {
            let dir = String(component)
            if isExecutableRegularFile(dir + "/" + name) {
                return dir
            }
        }
        return nil
    }
    #endif

    /// Options every swift-format invocation passes — the preflight probe included, so
    /// a `$SWIFT_FORMAT` binary too old to know one of them fails the probe rather than
    /// the build. `--follow-symlinks` because swift-format otherwise silently skips a
    /// source file that is a symlink, even when it is named explicitly.
    var commonSwiftFormatOptions: [String] {
        ["--parallel", "--follow-symlinks"]
    }

    /// The toolchain-selection variables the build-tool plugin forwards to its prebuild
    /// command. SwiftPM runs prebuild commands with a scrubbed environment, so without
    /// them `xcrun` in the lint would resolve the xcode-select toolchain even when the
    /// plugin — and its preflight probe — ran under a different `DEVELOPER_DIR`.
    func toolchainSelectionEnvironment() -> [String: String] {
        #if os(macOS)
        let environment = ProcessInfo.processInfo.environment
        var forwarded: [String: String] = [:]
        for key in ["DEVELOPER_DIR", "TOOLCHAINS"] {
            if let value = environment[key], !value.isEmpty {
                forwarded[key] = value
            }
        }
        return forwarded
        #else
        return [:]
        #endif
    }

    /// Pins `DEVELOPER_DIR` to the Xcode that owns `swiftFormat` — the host's own
    /// `swift-format` as `context.tool(named:)` reports it — unless the environment
    /// already selects a toolchain. Xcode runs plugins without `DEVELOPER_DIR`, so
    /// `xcrun` would otherwise resolve the xcode-select Xcode even when a different
    /// Xcode is running the build, and lint with the wrong swift-format. Everything
    /// downstream — the probe, its cache key, the forwarded prebuild environment —
    /// reads the variable, so setting it once keeps them all on the building Xcode.
    func pinDeveloperDirectory(toXcodeOf swiftFormat: URL?) {
        #if os(macOS)
        let environment = ProcessInfo.processInfo.environment
        guard (environment["DEVELOPER_DIR"] ?? "").isEmpty,
            (environment["TOOLCHAINS"] ?? "").isEmpty,
            let path = swiftFormat?.path(percentEncoded: false)
        else {
            return
        }
        // Only an Xcode's default toolchain maps back to a developer directory; a
        // standalone toolchain or a $PATH binary leaves xcrun's own choice in place.
        let suffix = "/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-format"
        guard path.hasSuffix(suffix) else {
            return
        }
        setenv("DEVELOPER_DIR", String(path.dropLast(suffix.count)), 1)
        #endif
    }

    // MARK: Configuration Resolution

    /// Looks for `.swift-format` in the downstream project root, falling back to an
    /// embedded default written to the plugin work directory.
    ///
    /// Returns nil — after emitting an error — when the configuration is unusable
    /// (unreadable, a directory, or not a JSON object). Callers must stop: every
    /// swift-format invocation would fail on it, and follow-up diagnostics would only
    /// misattribute the problem to the toolchain.
    func resolveConfiguration(
        launcher: SwiftFormatLauncher,
        projectRoot: URL,
        pluginWorkDirectory: URL
    ) throws -> String? {
        let resolvedPath: String
        let projectConfig = projectRoot.appendingPathComponent(".swift-format")
        if FileManager.default.fileExists(atPath: projectConfig.path) {
            Diagnostics.remark(
                "Using project configuration at \(projectConfig.path)."
            )
            resolvedPath = projectConfig.path
        } else {
            let fallbackURL = pluginWorkDirectory.appendingPathComponent("swift-format-fallback.json")
            // Rewrite only on change, so the file's mtime stays stable across builds.
            if (try? String(contentsOf: fallbackURL, encoding: .utf8)) != fallbackConfigJSON {
                try fallbackConfigJSON.write(to: fallbackURL, atomically: true, encoding: .utf8)
            }
            Diagnostics.remark(
                """
                No .swift-format found in project root, using the bundled fallback configuration.
                • Heirloom Logic Persnicket repository: https://github.com/HeirloomLogic/Persnicket
                • Swift Programming Language `swift-format` repository: https://github.com/swiftlang/swift-format
                • Rules reference: \
                https://github.com/swiftlang/swift-format/blob/main/Documentation/RuleDocumentation.md
                """
            )
            resolvedPath = fallbackURL.path
        }

        switch validateConfig(at: resolvedPath) {
        case .ok(let version):
            Diagnostics.remark(
                """
                swift-format plugin preflight:
                • config: \(resolvedPath)
                • version: \(version.map(String.init) ?? "unknown")
                • executable: \(launcher.displayCommand)
                """
            )
            return resolvedPath
        case .invalid(let reason):
            // swift-format's own report of this is "Unable to read configuration",
            // without naming the file — so name it here.
            Diagnostics.error(
                """
                The swift-format configuration at \(resolvedPath) is unusable: \(reason)
                Fix the file and try again.
                """
            )
            return nil
        }
    }

    /// Best-effort probe of the active swift-format's `--version` output.
    ///
    /// Surfaces the toolchain version that would otherwise be invisible in logs.
    func logSwiftFormatVersion(launcher: SwiftFormatLauncher) {
        let process = Process()
        process.executableURL = launcher.executable
        process.arguments = launcher.leadingArguments + ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output =
                String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Diagnostics.remark(
                "swift-format --version: \(output.isEmpty ? "(no output)" : output)"
            )
        } catch {
            Diagnostics.remark(
                "swift-format --version probe failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: Failure Classification

    /// Sorts a failed swift-format run by remedy, from its stderr.
    func classifySwiftFormatFailure(stderr: String) -> SwiftFormatFailure {
        let lower = stderr.lowercased()
        // xcrun's report when the active toolchain has no swift-format. (On Linux the
        // launcher is an absolute path that discovery verified, so a missing binary
        // surfaces as a launch error instead.)
        if lower.contains("unable to find utility") {
            return .missingExecutable
        }
        if lower.contains("unable to read configuration")
            || lower.contains("invalid configuration")
        {
            return .configuration
        }
        // swift-argument-parser's report of a flag this swift-format predates, such as
        // `--follow-symlinks` on a pre-6.0 `$SWIFT_FORMAT`.
        if lower.contains("unknown option") {
            return .unsupportedOption
        }
        return .other
    }

    /// "exit status N", or "terminated by signal N" when the process was killed —
    /// `terminationStatus` alone can't tell the two apart.
    func describeTermination(of process: Process) -> String {
        process.terminationReason == .uncaughtSignal
            ? "terminated by signal \(process.terminationStatus)"
            : "exit status \(process.terminationStatus)"
    }

    /// Explains a configuration swift-format refused; `outcome` says what the plugin
    /// does about it.
    func configFailureMessage(
        launcher: SwiftFormatLauncher,
        configPath: String,
        stderr: String,
        outcome: String
    ) -> String {
        var version: Int?
        if case .ok(let v) = validateConfig(at: configPath) { version = v }
        return """
            swift-format cannot use the configuration — \(outcome).

            Either the configuration contains a setting this swift-format rejects, or the \
            active toolchain's swift-format expects a different configuration schema. \
            swift-format's message below says which setting it could not read.

            --- swift-format stderr ---
            \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            ---------------------------

            • config: \(configPath)  (version: \(version.map(String.init) ?? "unknown"))
            • executable: \(launcher.displayCommand)
            • Fix: correct the setting, or align the toolchain with the configuration — \
            upgrade the toolchain, or pin the config to a schema the active toolchain accepts.
            """
    }

    /// Explains a swift-format that could not be launched at all; `outcome` says what
    /// the plugin does about it.
    func missingExecutableMessage(launcher: SwiftFormatLauncher, stderr: String, outcome: String) -> String {
        """
        swift-format could not be launched — \(outcome).

        The `swift-format` binary is missing from the active toolchain. This is a \
        toolchain/CI setup issue, not a source code or configuration problem.

        --- launcher stderr ---
        \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        -----------------------

        • executable: \(launcher.displayCommand)
        • Fix: install a Swift toolchain that bundles swift-format (Swift 6.0+), \
        or set the SWIFT_FORMAT environment variable to the absolute path of \
        a swift-format binary.
        """
    }

    // MARK: Preflight Probe

    /// Runs swift-format against a trivial file to verify it launches and accepts the
    /// config, caching a successful verdict so unchanged incremental builds pay nothing.
    /// `strict` must match the real lint: under `--strict`, a config warning such as an
    /// unrecognized rule fails the run, where otherwise it passes.
    ///
    /// This catches config/toolchain mismatches before SPM's prebuild command runs —
    /// where a non-zero exit would fail the build. The verdict is cached in the
    /// persistent per-target work directory, keyed on the config bytes and the resolved
    /// toolchain; on a cache hit the probe subprocess is skipped entirely. Only `.ok`
    /// is cached — any failure re-probes every build so the diagnostic keeps surfacing
    /// (and, in strict mode, keeps failing) until it is fixed.
    func probeSwiftFormat(
        launcher: SwiftFormatLauncher,
        configPath: String,
        strict: Bool,
        pluginWorkDirectory: URL
    ) -> ProbeResult {
        let cacheURL = pluginWorkDirectory.appendingPathComponent("preflight-cache.v2")
        let cacheKey = preflightCacheKey(configPath: configPath, launcher: launcher).map {
            "\($0)|strict:\(strict)"
        }
        if let cacheKey,
            let cached = try? String(contentsOf: cacheURL, encoding: .utf8),
            cached == cacheKey
        {
            Diagnostics.remark(
                "swift-format preflight: config and toolchain unchanged since last check — skipping probe."
            )
            return .ok
        }

        let probeFile = pluginWorkDirectory.appendingPathComponent("_swift_format_probe.swift")
        do {
            try "// probe\n".write(to: probeFile, atomically: true, encoding: .utf8)
        } catch {
            Diagnostics.remark(
                """
                swift-format preflight probe skipped: could not write probe \
                file (\(error.localizedDescription)).
                """
            )
            return .ok
        }

        let process = Process()
        process.executableURL = launcher.executable
        process.arguments =
            launcher.leadingArguments + ["lint"] + commonSwiftFormatOptions + (strict ? ["--strict"] : []) + [
                "--configuration",
                configPath,
                probeFile.path,
            ]

        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            // The prebuild command would fail to launch the same way.
            return .missingExecutable(stderr: error.localizedDescription)
        }
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationReason != .exit || process.terminationStatus != EXIT_SUCCESS else {
            if let cacheKey {
                try? cacheKey.write(to: cacheURL, atomically: true, encoding: .utf8)
            }
            return .ok
        }

        // The probe file is a lone comment, which no rule flags, so only a launch,
        // config, or toolchain problem can fail it — and would fail the real lint too.
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        switch classifySwiftFormatFailure(stderr: stderr) {
        case .missingExecutable:
            return .missingExecutable(stderr: stderr)
        case .configuration:
            return .configError(stderr: stderr)
        case .other where strict && stderr.lowercased().contains("unrecognized rule"):
            // Only a warning, but `--strict` fails the run on it, and the probe file
            // has nothing else to fail on.
            return .configError(stderr: stderr)
        case .unsupportedOption, .other:
            return .failed(stderr: stderr, termination: describeTermination(of: process))
        }
    }

    /// A cheap, subprocess-free fingerprint of everything that changes the probe
    /// verdict: the config's bytes, how the toolchain is selected, and the swift-format
    /// binary that will run. Returns nil when the config cannot be read, which forces
    /// the probe to run.
    private func preflightCacheKey(configPath: String, launcher: SwiftFormatLauncher) -> String? {
        guard let configData = try? Data(contentsOf: URL(fileURLWithPath: configPath)) else {
            return nil
        }
        var parts = [
            "config:\(configData.count):\(stableHash(configData))",
            "exec:\(launcher.displayCommand)",
        ]
        #if os(macOS)
        let environment = ProcessInfo.processInfo.environment
        parts.append("DEVELOPER_DIR=\(environment["DEVELOPER_DIR"] ?? "")")
        parts.append("TOOLCHAINS=\(environment["TOOLCHAINS"] ?? "")")
        #endif
        // Size, mtime, and inode of the real binary catch an in-place toolchain update
        // (an App Store Xcode update, a retargeted symlink) that leaves every path as is.
        if let binary = swiftFormatBinaryPath(launcher: launcher) {
            let realPath = URL(fileURLWithPath: binary).resolvingSymlinksInPath().path
            if let attributes = try? FileManager.default.attributesOfItem(atPath: realPath) {
                let size = (attributes[.size] as? Int) ?? -1
                let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                let inode = (attributes[.systemFileNumber] as? Int) ?? -1
                parts.append("bin:\(realPath):\(size):\(mtime):\(inode)")
            }
        }
        return parts.joined(separator: "|")
    }

    /// The swift-format binary `launcher` will run, located without spawning a process.
    /// For `xcrun` this mirrors its default lookup — `DEVELOPER_DIR`, else the
    /// xcode-select link, else the Command Line Tools — and returns nil if the binary
    /// is not where that lookup expects (a `TOOLCHAINS` override is keyed separately).
    private func swiftFormatBinaryPath(launcher: SwiftFormatLauncher) -> String? {
        #if os(macOS)
        guard launcher.executable.path == "/usr/bin/xcrun" else {
            return launcher.executable.path
        }
        var developerDir: String
        if let fromEnvironment = ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
            !fromEnvironment.isEmpty
        {
            developerDir = fromEnvironment
        } else if let selected = try? FileManager.default.destinationOfSymbolicLink(
            atPath: "/var/db/xcode_select_link"
        ) {
            developerDir = selected
        } else {
            developerDir = "/Library/Developer/CommandLineTools"
        }
        // DEVELOPER_DIR may name the Xcode bundle itself rather than its Developer dir.
        if developerDir.hasSuffix(".app") || developerDir.hasSuffix(".app/") {
            developerDir = URL(fileURLWithPath: developerDir).appendingPathComponent("Contents/Developer").path
        }
        let candidates = [
            developerDir + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-format",
            developerDir + "/usr/bin/swift-format",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
        #else
        return launcher.executable.path
        #endif
    }

    /// A deterministic djb2 hash. `Hasher` is unsuitable here — it is seeded per
    /// process, so its output would differ between builds and never cache-hit.
    private func stableHash(_ data: Data) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in data {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return hash
    }

    /// Emits the diagnostic for a failed preflight probe. Non-strict builds get a
    /// warning and linting is skipped; strict builds get an error — silently skipping
    /// the lint would defeat the hard gate the user opted into.
    func emitProbeFailure(
        _ result: ProbeResult,
        launcher: SwiftFormatLauncher,
        configPath: String,
        strict: Bool
    ) {
        let outcome = strict ? "failing the build (strict mode)" : "linting skipped"
        let message: String
        switch result {
        case .ok:
            return
        case .configError(let stderr):
            message = configFailureMessage(
                launcher: launcher,
                configPath: configPath,
                stderr: stderr,
                outcome: outcome
            )
        case .missingExecutable(let stderr):
            message = missingExecutableMessage(launcher: launcher, stderr: stderr, outcome: outcome)
        case .failed(let stderr, let termination):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            message = """
                swift-format failed its preflight check (\(termination)) — \(outcome).

                The check lints a one-line file, so the real lint would fail the same way.

                --- swift-format stderr ---
                \(trimmed.isEmpty ? "(empty)" : trimmed)
                ---------------------------

                • config: \(configPath)
                • executable: \(launcher.displayCommand)
                """
        }
        if strict {
            Diagnostics.error(message)
        } else {
            Diagnostics.warning(message)
        }
    }

    // MARK: Strict Mode

    /// Whether Persnoop should pass `--strict` to `swift-format lint`, which makes
    /// lint violations exit non-zero and halt the build before compilation.
    ///
    /// Opt in with either the `PERSNICKET_STRICT` environment variable set to `1`,
    /// `true`, or `yes` (case-insensitive), or a `.persnicket-strict` sentinel file
    /// in the project root. The environment variable is convenient for CI and
    /// `swift build`, but is not visible to Xcode GUI builds, which do not inherit
    /// the shell environment; the sentinel file works everywhere.
    ///
    /// The sentinel takes precedence: when it is present, the environment variable
    /// cannot turn strict mode off.
    func strictModeEnabled(projectRoot: URL) -> Bool {
        let sentinel = projectRoot.appendingPathComponent(".persnicket-strict")
        if FileManager.default.fileExists(atPath: sentinel.path) {
            Diagnostics.remark(
                "Persnoop strict mode enabled (.persnicket-strict) — lint violations will fail the build."
            )
            return true
        }
        if let value = ProcessInfo.processInfo.environment["PERSNICKET_STRICT"] {
            let normalized = value.lowercased()
            if ["1", "true", "yes"].contains(normalized) {
                Diagnostics.remark(
                    "Persnoop strict mode enabled (PERSNICKET_STRICT) — lint violations will fail the build."
                )
                return true
            }
            if !normalized.isEmpty, !["0", "false", "no"].contains(normalized) {
                Diagnostics.warning(
                    """
                    PERSNICKET_STRICT is set to "\(value)", which is not a recognized \
                    value — treating strict mode as off. Use 1, true, or yes to enable \
                    it; 0, false, no, or unset to disable it.
                    """
                )
            }
        }
        return false
    }
}

/// How to launch `swift-format` on the current host.
///
/// `executable` is the absolute path to spawn; `leadingArguments` are prepended
/// before any swift-format CLI args. macOS uses `xcrun swift-format`; Linux uses
/// the resolved binary directly with no leading arguments.
struct SwiftFormatLauncher {
    let executable: URL
    let leadingArguments: [String]

    /// Human-readable rendering for diagnostic logs.
    var displayCommand: String {
        leadingArguments.isEmpty
            ? executable.path
            : executable.path + " " + leadingArguments.joined(separator: " ")
    }
}

enum ProbeResult {
    case ok
    case configError(stderr: String)
    case missingExecutable(stderr: String)
    case failed(stderr: String, termination: String)
}

enum SwiftFormatFailure {
    case missingExecutable
    case configuration
    case unsupportedOption
    case other
}

struct PluginError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

enum ConfigValidation {
    case ok(version: Int?)
    case invalid(reason: String)
}

/// Parses the swift-format config at `path` and returns its `version` field if present.
///
/// Parses as JSON5 — comments, trailing commas, unquoted keys — because swift-format
/// itself does from 602 (Swift 6.2) on, so a config it accepts must not be rejected
/// here. On an older toolchain, JSON5 syntax fails the preflight probe instead, as
/// the config/toolchain mismatch it is.
func validateConfig(at path: String) -> ConfigValidation {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
        return .invalid(reason: "it is a directory, not a file.")
    }
    let data: Data
    do {
        data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
        return .invalid(reason: "could not read file: \(error.localizedDescription)")
    }
    let decoder = JSONDecoder()
    decoder.allowsJSON5 = true
    do {
        return .ok(version: try decoder.decode(ConfigHeader.self, from: data).version)
    } catch DecodingError.typeMismatch, DecodingError.valueNotFound {
        // `valueNotFound` is a top-level `null`.
        return .invalid(reason: "the top-level JSON value is not an object.")
    } catch DecodingError.dataCorrupted(let context) {
        // The underlying parser error carries the line and column.
        let underlying = context.underlyingError.map { $0 as NSError }
        let detail = underlying?.userInfo[NSDebugDescriptionErrorKey] as? String
        return .invalid(reason: "not valid JSON: \(detail ?? context.debugDescription)")
    } catch {
        return .invalid(reason: "not valid JSON: \(error)")
    }
}

/// The one field of a swift-format configuration the plugins read. Decoding it also
/// checks that the file is a JSON object.
private struct ConfigHeader: Decodable {
    let version: Int?

    private enum CodingKeys: String, CodingKey {
        case version
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Only shown in diagnostics; a malformed version is swift-format's to report.
        version = try? container.decodeIfPresent(Int.self, forKey: .version)
    }
}

// MARK: - Embedded Fallback Configuration

/// The default `.swift-format` configuration shipped with this plugin.
///
/// Downstream projects can override this by placing their own `.swift-format`
/// in the project root.
///
/// GENERATED: this literal is rewritten by `bin/regenerate-embedded-fallback`
/// from the canonical `.swift-format` at the repo root. Do not edit by hand —
/// edit `.swift-format` and run the regenerator. SwiftPM plugin targets cannot
/// share Swift source or carry resources, so both plugins embed a copy.
private let fallbackConfigJSON = """
    {
      "fileScopedDeclarationPrivacy": {
        "accessLevel": "private"
      },
      "indentConditionalCompilationBlocks": false,
      "indentBlankLines": false,
      "indentSwitchCaseLabels": false,
      "indentation": {
        "spaces": 4
      },
      "lineBreakAroundMultilineExpressionChainComponents": false,
      "lineBreakBeforeControlFlowKeywords": false,
      "lineBreakBeforeEachArgument": false,
      "lineBreakBeforeEachGenericRequirement": false,
      "lineBreakBetweenDeclarationAttributes": false,
      "lineLength": 120,
      "maximumBlankLines": 1,
      "multiElementCollectionTrailingCommas": true,
      "noAssignmentInExpressions": {
        "allowedFunctions": [
          "XCTAssertNoThrow"
        ]
      },
      "prioritizeKeepingFunctionOutputTogether": true,
      "reflowMultilineStringLiterals": "onlyLinesOverLength",
      "respectsExistingLineBreaks": true,
      "rules": {
        "AllPublicDeclarationsHaveDocumentation": true,
        "AlwaysUseLiteralForEmptyCollectionInit": false,
        "AlwaysUseLowerCamelCase": true,
        "AmbiguousTrailingClosureOverload": true,
        "AvoidRetroactiveConformances": true,
        "BeginDocumentationCommentWithOneLineSummary": false,
        "DoNotUseSemicolons": true,
        "DontRepeatTypeInStaticProperties": true,
        "FileScopedDeclarationPrivacy": true,
        "FullyIndirectEnum": true,
        "GroupNumericLiterals": true,
        "IdentifiersMustBeASCII": true,
        "NeverForceUnwrap": true,
        "NeverUseForceTry": true,
        "NeverUseImplicitlyUnwrappedOptionals": true,
        "NoAccessLevelOnExtensionDeclaration": true,
        "NoAssignmentInExpressions": true,
        "NoBlockComments": true,
        "NoCasesWithOnlyFallthrough": true,
        "NoEmptyLinesOpeningClosingBraces": true,
        "NoEmptyTrailingClosureParentheses": true,
        "NoLabelsInCasePatterns": true,
        "NoLeadingUnderscores": true,
        "NoParensAroundConditions": true,
        "NoPlaygroundLiterals": true,
        "NoVoidReturnOnFunctionSignature": true,
        "OmitExplicitReturns": true,
        "OneCasePerLine": true,
        "OneVariableDeclarationPerLine": true,
        "OnlyOneTrailingClosureArgument": true,
        "OrderedImports": true,
        "ReplaceForEachWithForLoop": true,
        "ReturnVoidInsteadOfEmptyTuple": true,
        "TypeNamesShouldBeCapitalized": true,
        "UseEarlyExits": true,
        "UseExplicitNilCheckInConditions": true,
        "UseLetInEveryBoundCaseVariable": true,
        "UseShorthandTypeNames": true,
        "UseSingleLinePropertyGetter": true,
        "UseSynthesizedInitializer": true,
        "UseTripleSlashForDocumentationComments": true,
        "UseWhereClausesInForLoops": true,
        "ValidateDocumentationComments": true
      },
      "spacesAroundRangeFormationOperators": false,
      "spacesBeforeEndOfLineComments": 2,
      "tabWidth": 4,
      "version": 1
    }
    """
