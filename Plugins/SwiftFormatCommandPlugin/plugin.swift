import Foundation
import PackagePlugin

@main
struct SwiftFormatCommandPlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) throws {
        let launcher = swiftFormatLauncher()

        let configPath = try resolveConfiguration(
            launcher: launcher,
            projectRoot: context.package.directoryURL,
            pluginWorkDirectory: context.pluginWorkDirectoryURL
        )

        logSwiftFormatVersion(launcher: launcher)

        for target in context.package.targets {
            guard let sourceModule = target as? SourceModuleTarget else {
                Diagnostics.remark(
                    "Skipping target \"\(target.name)\" because it is not a source module."
                )
                continue
            }

            let sourceFiles = sourceModule.sourceFiles(withSuffix: ".swift")
            guard !sourceFiles.isEmpty else {
                Diagnostics.remark(
                    "Skipping target \"\(target.name)\" because it has no Swift source files."
                )
                continue
            }

            try format(
                launcher: launcher,
                sourceFiles: sourceFiles,
                targetName: target.name,
                configPath: configPath
            )
        }
    }

    func format(
        launcher: SwiftFormatLauncher,
        sourceFiles: FileList,
        targetName: String,
        configPath: String
    ) throws {
        var arguments =
            launcher.leadingArguments + [
                "format",
                "--in-place",
                "--parallel",
                "--configuration", configPath,
            ]

        let swiftFiles = sourceFiles.filter {
            $0.type == .source && $0.url.pathExtension == "swift"
        }
        arguments += swiftFiles.map { $0.url.path(percentEncoded: false) }

        let process = Process()
        process.executableURL = launcher.executable
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationReason == .exit, process.terminationStatus == EXIT_SUCCESS else {
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let lower = stderr.lowercased()
            let isConfigError =
                lower.contains("unable to read configuration")
                || lower.contains("invalid configuration")
                || lower.contains("unknown argument")

            if isConfigError {
                var version: Int?
                if case .ok(let v) = validateConfig(at: configPath) { version = v }
                let versionString = version.map(String.init) ?? "unknown"
                Diagnostics.warning(
                    """
                    swift-format cannot parse the configuration — formatting skipped for \
                    target "\(targetName)".

                    The active toolchain's swift-format is incompatible with the config schema. \
                    This is a CI/toolchain setup issue, not a source code problem.

                    --- swift-format stderr ---
                    \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                    ---------------------------

                    • config: \(configPath)  (version: \(versionString))
                    • executable: \(launcher.displayCommand)
                    • Fix: upgrade the toolchain to match the config schema, or pin \
                    the config to an older schema compatible with the active toolchain.
                    """
                )
                return
            }

            let message =
                """
                swift-format format failed for target "\(targetName)" \
                (status \(process.terminationStatus)).
                --- swift-format stderr ---
                \(stderr.isEmpty ? "(empty)" : stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                ---------------------------
                """
            Diagnostics.error(message)
            throw PluginError(message: message)
        }

        Diagnostics.remark("Formatted Swift source files in target \"\(targetName)\".")
    }

    // MARK: - Shared Plugin Infrastructure (must be identical across all plugin targets)

    /// Resolves how to invoke `swift-format` on the current platform.
    ///
    /// **macOS:** dispatches through `/usr/bin/xcrun` so the binary tracks the active
    /// Xcode toolchain.
    ///
    /// **Linux:** auto-discovers the toolchain's `swift-format` so downstream consumers
    /// don't have to symlink it into `/usr/local/bin` from CI. See `resolveLinuxSwiftFormatPath`
    /// for the search order.
    ///
    /// If Linux discovery fails, emits a `Diagnostics.error` listing the searched paths
    /// and falls back to `/usr/bin/env swift-format` — which still fails at launch, but
    /// the error above the failure now explains why.
    private func swiftFormatLauncher() -> SwiftFormatLauncher {
        #if os(macOS)
        return SwiftFormatLauncher(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            leadingArguments: ["swift-format"]
        )
        #else
        if let resolved = resolveLinuxSwiftFormatPath() {
            return SwiftFormatLauncher(
                executable: URL(fileURLWithPath: resolved),
                leadingArguments: []
            )
        }
        Diagnostics.error(
            """
            swift-format binary not found.

            Searched (in order):
              1. $SWIFT_FORMAT environment variable
              2. Sibling of `swift` on $PATH (canonical Swift toolchain location)
              3. /usr/local/bin/swift-format
              4. /usr/bin/swift-format
              5. swift-format on $PATH

            Most Linux Swift toolchains ship swift-format in the same directory as `swift`. \
            If your setup differs, set the SWIFT_FORMAT environment variable to an absolute path. \
            See https://github.com/HeirloomLogic/SwiftFormatPlugin#how-it-works
            """
        )
        return SwiftFormatLauncher(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            leadingArguments: ["swift-format"]
        )
        #endif
    }

    #if !os(macOS)
    /// Walks the Linux discovery chain and returns the first executable swift-format
    /// it finds, or nil if no candidate exists.
    private func resolveLinuxSwiftFormatPath() -> String? {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment

        if let override = env["SWIFT_FORMAT"], !override.isEmpty {
            if fm.isExecutableFile(atPath: override) {
                return override
            }
            Diagnostics.warning(
                """
                $SWIFT_FORMAT is set to "\(override)" but it is not an executable file. \
                Falling back to toolchain discovery.
                """
            )
        }

        if let swiftDir = directoryContainingExecutable(named: "swift", env: env) {
            let candidate = swiftDir + "/swift-format"
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        for candidate in ["/usr/local/bin/swift-format", "/usr/bin/swift-format"]
        where fm.isExecutableFile(atPath: candidate) {
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
        let fm = FileManager.default
        for component in pathVar.split(separator: ":", omittingEmptySubsequences: true) {
            let dir = String(component)
            if fm.isExecutableFile(atPath: dir + "/" + name) {
                return dir
            }
        }
        return nil
    }
    #endif

    // MARK: Configuration Resolution

    /// Looks for `.swift-format` in the downstream project root.
    ///
    /// Falls back to an embedded default written to the plugin work directory.
    func resolveConfiguration(
        launcher: SwiftFormatLauncher,
        projectRoot: URL,
        pluginWorkDirectory: URL
    ) throws -> String {
        let resolvedPath: String
        let projectConfig = projectRoot.appendingPathComponent(".swift-format")
        if FileManager.default.fileExists(atPath: projectConfig.path) {
            Diagnostics.remark(
                "Using project configuration at \(projectConfig.path)."
            )
            resolvedPath = projectConfig.path
        } else {
            let fallbackURL = pluginWorkDirectory.appendingPathComponent("swift-format-fallback.json")
            try fallbackConfigJSON.write(to: fallbackURL, atomically: true, encoding: .utf8)
            Diagnostics.remark(
                """
                No .swift-format found in project root, using the bundled fallback configuration.
                • Heirloom Logic SwiftFormatPlugin repository: https://github.com/HeirloomLogic/SwiftFormatPlugin
                • Swift Programming Language `swift-format` repository: https://github.com/swiftlang/swift-format
                • Rules reference: \
                https://github.com/swiftlang/swift-format/blob/main/Documentation/RuleDocumentation.md
                """
            )
            resolvedPath = fallbackURL.path
        }

        emitPreflightDiagnostics(launcher: launcher, configPath: resolvedPath)
        return resolvedPath
    }

    /// Emits an up-front summary of the config/toolchain so that when swift-format
    /// fails downstream with its cryptic `<unknown>: error: Unable to read configuration`,
    /// the context needed to diagnose the failure is already in the log above it.
    private func emitPreflightDiagnostics(launcher: SwiftFormatLauncher, configPath: String) {
        switch validateConfig(at: configPath) {
        case .ok(let version):
            let versionString = version.map(String.init) ?? "unknown"
            Diagnostics.remark(
                """
                swift-format plugin preflight:
                • config: \(configPath)
                • version: \(versionString)
                • executable: \(launcher.displayCommand)

                • If swift-format reports "Unable to read configuration", the most likely cause \
                is a mismatch between the active toolchain's bundled swift-format and the schema \
                used by this config. The config "version" field does not always change between \
                incompatible schemas, so breaks can be silent.
                """
            )
        case .invalid(let reason):
            Diagnostics.error(
                """
                The swift-format configuration at \(configPath) failed to parse as JSON: \(reason)
                • swift-format reports "<unknown>: error: Unable to read configuration" without \
                  naming the file. Please fix the JSON above before rerunning.
                """
            )
        }
    }

    /// Best-effort probe of the active swift-format's `--version` output.
    ///
    /// Surfaces the toolchain version that would otherwise be invisible in logs.
    private func logSwiftFormatVersion(launcher: SwiftFormatLauncher) {
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

    // MARK: Preflight Probe

    /// Runs swift-format against a trivial file to verify the config is parseable.
    ///
    /// This catches config/toolchain mismatches before SPM's prebuild command
    /// runs — where a non-zero exit would fail the build.
    func probeSwiftFormat(
        launcher: SwiftFormatLauncher,
        configPath: String,
        pluginWorkDirectory: URL
    ) -> ProbeResult {
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
            launcher.leadingArguments + [
                "lint",
                "--configuration",
                configPath,
                probeFile.path,
            ]

        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        do {
            try process.run()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus != EXIT_SUCCESS else {
                return .ok
            }

            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let lower = stderr.lowercased()
            if lower.contains("unable to read configuration")
                || lower.contains("invalid configuration")
                || lower.contains("unknown argument")
                || lower.contains("unable to find utility")
            {
                return .configError(stderr: stderr)
            }
            Diagnostics.remark(
                """
                swift-format preflight probe exited with status \(process.terminationStatus) \
                for an unrecognized reason. Linting will proceed — if it fails, check the \
                stderr output above.
                """
            )
            return .ok
        } catch {
            Diagnostics.remark(
                """
                swift-format preflight probe skipped: could not launch \
                process (\(error.localizedDescription)).
                """
            )
            return .ok
        }
    }

    /// Emits a detailed warning when the preflight probe detects a config/toolchain
    /// mismatch, and explains that linting has been skipped.
    func emitConfigWarning(launcher: SwiftFormatLauncher, configPath: String, stderr: String) {
        var version: Int?
        if case .ok(let v) = validateConfig(at: configPath) { version = v }
        let versionString = version.map(String.init) ?? "unknown"
        Diagnostics.warning(
            """
            swift-format cannot parse the configuration — linting skipped.

            The active toolchain's swift-format is incompatible with the config schema. \
            This is a CI/toolchain setup issue, not a source code problem.

            --- swift-format stderr ---
            \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            ---------------------------

            • config: \(configPath)  (version: \(versionString))
            • executable: \(launcher.displayCommand)
            • Fix: upgrade the toolchain to match the config schema, or pin \
            the config to an older schema compatible with the active toolchain.
            """
        )
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
func validateConfig(at path: String) -> ConfigValidation {
    let url = URL(fileURLWithPath: path)
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        return .invalid(reason: "could not read file: \(error.localizedDescription)")
    }
    do {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            return .invalid(reason: "top-level JSON value is not an object")
        }
        return .ok(version: dict["version"] as? Int)
    } catch {
        return .invalid(reason: error.localizedDescription)
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
