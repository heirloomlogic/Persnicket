#if canImport(XcodeProjectPlugin)
import Foundation
import PackagePlugin
import XcodeProjectPlugin

extension SwiftFormatBuildToolPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(
        context: XcodePluginContext,
        target: XcodeTarget
    ) throws -> [Command] {
        let configPath = try resolveConfiguration(
            projectRoot: context.xcodeProject.directoryURL,
            pluginWorkDirectory: context.pluginWorkDirectoryURL
        )

        if case .configError(let stderr) = probeSwiftFormat(
            configPath: configPath,
            pluginWorkDirectory: context.pluginWorkDirectoryURL
        ) {
            emitConfigWarning(configPath: configPath, stderr: stderr)
            return []
        }

        return [
            .prebuildCommand(
                displayName: "swift-format lint (\(target.displayName))",
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: [
                    "swift-format", "lint",
                    "--parallel",
                    "--configuration", configPath,
                    "--recursive",
                    context.xcodeProject.directoryURL.path(percentEncoded: false),
                ],
                outputFilesDirectory: context.pluginWorkDirectoryURL
            )
        ]
    }
}
#endif
