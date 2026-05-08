#if canImport(XcodeProjectPlugin)
import Foundation
import PackagePlugin
import XcodeProjectPlugin

extension SwiftFormatBuildToolPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(
        context: XcodePluginContext,
        target: XcodeTarget
    ) throws -> [Command] {
        let launcher = swiftFormatLauncher()

        let configPath = try resolveConfiguration(
            launcher: launcher,
            projectRoot: context.xcodeProject.directoryURL,
            pluginWorkDirectory: context.pluginWorkDirectoryURL
        )

        if case .configError(let stderr) = probeSwiftFormat(
            launcher: launcher,
            configPath: configPath,
            pluginWorkDirectory: context.pluginWorkDirectoryURL
        ) {
            emitConfigWarning(launcher: launcher, configPath: configPath, stderr: stderr)
            return []
        }

        return [
            .prebuildCommand(
                displayName: "swift-format lint (\(target.displayName))",
                executable: launcher.executable,
                arguments: launcher.leadingArguments + [
                    "lint",
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
