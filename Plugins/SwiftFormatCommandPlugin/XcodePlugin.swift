#if canImport(XcodeProjectPlugin)
import Foundation
import PackagePlugin
import XcodeProjectPlugin

extension SwiftFormatCommandPlugin: XcodeCommandPlugin {
    func performCommand(
        context: XcodePluginContext,
        arguments: [String]
    ) throws {
        let configPath = try resolveConfiguration(
            projectRoot: context.xcodeProject.directoryURL,
            pluginWorkDirectory: context.pluginWorkDirectoryURL
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "swift-format", "format",
            "--in-place",
            "--parallel",
            "--configuration", configPath,
            "--recursive",
            context.xcodeProject.directoryURL.path,
        ]

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

            Diagnostics.error(
                "swift-format format failed for project "
                    + "\"\(context.xcodeProject.displayName)\" "
                    + "(status \(process.terminationStatus))."
            )
            return
        }

        Diagnostics.remark(
            "Formatted Swift source files in project \"\(context.xcodeProject.displayName)\"."
        )
    }
}
#endif
