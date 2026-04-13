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

        try process.run()
        process.waitUntilExit()

        guard
            process.terminationReason == .exit,
            process.terminationStatus == EXIT_SUCCESS
        else {
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
