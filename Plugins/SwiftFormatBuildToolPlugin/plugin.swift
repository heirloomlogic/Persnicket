import Foundation
import PackagePlugin

@main
struct SwiftFormatBuildToolPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        guard let sourceModule = target as? SourceModuleTarget else {
            return []
        }

        let sourceFiles = sourceModule.sourceFiles(withSuffix: ".swift")
        guard !sourceFiles.isEmpty else {
            return []
        }

        let configPath = try resolveConfiguration(
            projectRoot: context.package.directoryURL,
            pluginWorkDirectory: context.pluginWorkDirectoryURL
        )

        var arguments: [String] = [
            "swift-format", "lint",
            "--parallel",
            "--configuration", configPath,
        ]
        for file in sourceFiles {
            arguments.append(file.url.path)
        }

        return [
            .prebuildCommand(
                displayName: "swift-format lint (\(target.name))",
                executable: swiftFormatExecutable(),
                arguments: arguments,
                outputFilesDirectory: context.pluginWorkDirectoryURL
            )
        ]
    }

    /// Returns the executable URL used to invoke `swift-format`.
    ///
    /// On macOS this is `xcrun` (resolves from the active Xcode toolchain).
    /// On Linux / Windows the binary is expected on `$PATH`.
    private func swiftFormatExecutable() -> URL {
        #if os(macOS)
        URL(fileURLWithPath: "/usr/bin/xcrun")
        #else
        URL(fileURLWithPath: "/usr/bin/env")
        #endif
    }

    // MARK: - Configuration Resolution

    /// Looks for `.swift-format` in the downstream project root.
    ///
    /// Falls back to an embedded default written to the plugin work directory.
    func resolveConfiguration(
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
                • To learn about swift-format, go to https://github.com/swiftlang/swift-format
                • Rules reference: https://github.com/swiftlang/swift-format/blob/main/Documentation/RuleDocumentation.md
                """
            )
            resolvedPath = fallbackURL.path
        }

        emitPreflightDiagnostics(configPath: resolvedPath)
        return resolvedPath
    }

    /// Emits an up-front summary of the config/toolchain so that when swift-format
    /// fails downstream with its cryptic `<unknown>: error: Unable to read configuration`,
    /// the context needed to diagnose the failure is already in the log above it.
    private func emitPreflightDiagnostics(configPath: String) {
        switch validateConfig(at: configPath) {
        case .ok(let version):
            let versionString = version.map(String.init) ?? "unknown"
            Diagnostics.remark(
                """
                swift-format plugin preflight:
                • config: \(configPath)
                • version: \(versionString)
                • executable: \(swiftFormatExecutable().path) swift-format

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
      "indentSwitchCaseLabels": false,
      "indentation": {
        "spaces": 4
      },
      "lineBreakAroundMultilineExpressionChainComponents": false,
      "lineBreakBeforeControlFlowKeywords": false,
      "lineBreakBeforeEachArgument": true,
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
      "reflowMultilineStringLiterals": {
        "never": { }
      },
      "respectsExistingLineBreaks": true,
      "rules": {
        "AllPublicDeclarationsHaveDocumentation": true,
        "AlwaysUseLiteralForEmptyCollectionInit": false,
        "AlwaysUseLowerCamelCase": true,
        "AmbiguousTrailingClosureOverload": true,
        "AvoidRetroactiveConformances": true,
        "BeginDocumentationCommentWithOneLineSummary": true,
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
        "UseEarlyExits": false,
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
