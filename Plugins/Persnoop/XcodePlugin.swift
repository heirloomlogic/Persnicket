#if canImport(XcodeProjectPlugin)
import Foundation
import PackagePlugin
import XcodeProjectPlugin

extension Persnoop: XcodeBuildToolPlugin {
    func createBuildCommands(
        context: XcodePluginContext,
        target: XcodeTarget
    ) throws -> [Command] {
        let swiftFiles = target.inputFiles.filter {
            $0.type == .source && $0.url.pathExtension == "swift"
        }
        guard !swiftFiles.isEmpty else {
            Diagnostics.remark(
                "Skipping target \"\(target.displayName)\" because it has no Swift source files."
            )
            return []
        }

        let launcher = swiftFormatLauncher()

        let configPath = try resolveConfiguration(
            launcher: launcher,
            projectRoot: context.xcodeProject.directoryURL,
            pluginWorkDirectory: context.pluginWorkDirectoryURL
        )

        let strict = strictModeEnabled(projectRoot: context.xcodeProject.directoryURL)

        switch probeSwiftFormat(
            launcher: launcher,
            configPath: configPath,
            pluginWorkDirectory: context.pluginWorkDirectoryURL
        ) {
        case .ok:
            break
        case .configError(let stderr):
            emitConfigFailure(launcher: launcher, configPath: configPath, stderr: stderr, strict: strict)
            return []
        case .missingExecutable(let stderr):
            emitMissingExecutableFailure(launcher: launcher, stderr: stderr, strict: strict)
            return []
        }

        var arguments =
            launcher.leadingArguments + [
                "lint",
                "--parallel",
                "--configuration", configPath,
            ]
        if strict {
            arguments.append("--strict")
        }
        for file in swiftFiles {
            arguments.append(file.url.path(percentEncoded: false))
        }

        let outputsDir = context.pluginWorkDirectoryURL.appendingPathComponent(
            "outputs",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputsDir,
            withIntermediateDirectories: true
        )

        return [
            .prebuildCommand(
                displayName: "swift-format lint (\(target.displayName))",
                executable: launcher.executable,
                arguments: arguments,
                outputFilesDirectory: outputsDir
            )
        ]
    }
}
#endif
