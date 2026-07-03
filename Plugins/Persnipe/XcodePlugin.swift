#if canImport(XcodeProjectPlugin)
import Foundation
import PackagePlugin
import XcodeProjectPlugin

extension Persnipe: XcodeCommandPlugin {
    func performCommand(
        context: XcodePluginContext,
        arguments: [String]
    ) throws {
        // Argument handling mirrors the SPM `Persnipe.performCommand` variant so the
        // two behave identically. This block lives outside the byte-identical shared
        // section, so keep it in sync with the SPM variant by hand.
        var argumentExtractor = ArgumentExtractor(arguments)
        let targetNames = argumentExtractor.extractOption(named: "target")
        let unrecognized = argumentExtractor.remainingArguments
        guard unrecognized.isEmpty else {
            let message =
                """
                Unrecognized arguments: \(unrecognized.joined(separator: " ")). \
                Persnipe accepts --target <name> (repeatable, space-separated — \
                --target=<name> is not supported) to limit formatting to specific targets.
                """
            Diagnostics.error(message)
            throw PluginError(message: message)
        }

        let requestedTargets: [XcodeTarget]
        if targetNames.isEmpty {
            requestedTargets = context.xcodeProject.targets
        } else {
            let targetsByName = Dictionary(
                context.xcodeProject.targets.map { ($0.displayName, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            requestedTargets = try targetNames.map { name in
                guard let target = targetsByName[name] else {
                    let message =
                        "No target named \"\(name)\" in project \"\(context.xcodeProject.displayName)\"."
                    Diagnostics.error(message)
                    throw PluginError(message: message)
                }
                return target
            }
        }

        let launcher = swiftFormatLauncher()

        let configPath = try resolveConfiguration(
            launcher: launcher,
            projectRoot: context.xcodeProject.directoryURL,
            pluginWorkDirectory: context.pluginWorkDirectoryURL
        )

        // Format only the Swift sources that belong to the requested targets.
        // Formatting the project directory recursively would also rewrite
        // vendored and generated Swift code that the project doesn't own.
        var seenPaths = Set<String>()
        var swiftFilePaths: [String] = []
        for target in requestedTargets {
            for file in target.inputFiles
            where file.type == .source && file.url.pathExtension == "swift" {
                let path = file.url.path(percentEncoded: false)
                if seenPaths.insert(path).inserted {
                    swiftFilePaths.append(path)
                }
            }
        }

        guard !swiftFilePaths.isEmpty else {
            Diagnostics.remark(
                """
                Skipping project "\(context.xcodeProject.displayName)" because its targets \
                have no Swift source files.
                """
            )
            return
        }

        let process = Process()
        process.executableURL = launcher.executable
        process.arguments =
            launcher.leadingArguments + [
                "format",
                "--in-place",
                "--parallel",
                "--configuration", configPath,
            ] + swiftFilePaths

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard
            process.terminationReason == .exit,
            process.terminationStatus == EXIT_SUCCESS
        else {
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let lower = stderr.lowercased()
            let isConfigError =
                lower.contains("unable to read configuration")
                || lower.contains("invalid configuration")
                || lower.contains("unknown argument")

            if isConfigError {
                Diagnostics.warning(
                    """
                    swift-format cannot parse the configuration — formatting skipped for \
                    project "\(context.xcodeProject.displayName)".

                    The active toolchain's swift-format is incompatible with the config schema. \
                    This is a CI/toolchain setup issue, not a source code problem.

                    --- swift-format stderr ---
                    \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                    ---------------------------

                    • config: \(configPath)
                    • Fix: upgrade the toolchain to match the config schema, or pin \
                    the config to an older schema compatible with the active toolchain.
                    """
                )
                return
            }

            let message =
                """
                swift-format format failed for project \
                "\(context.xcodeProject.displayName)" \
                (status \(process.terminationStatus)).
                --- swift-format stderr ---
                \(stderr.isEmpty ? "(empty)" : stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                ---------------------------
                """
            Diagnostics.error(message)
            throw PluginError(message: message)
        }

        Diagnostics.remark(
            "Formatted Swift source files in project \"\(context.xcodeProject.displayName)\"."
        )
    }
}
#endif
