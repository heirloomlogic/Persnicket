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

        pinDeveloperDirectory(toXcodeOf: try? context.tool(named: "swift-format").url)
        return try lintCommands(
            targetName: target.displayName,
            sourceFiles: swiftFiles.map(\.url),
            projectRoot: context.xcodeProject.directoryURL,
            pluginWorkDirectory: context.pluginWorkDirectoryURL
        )
    }
}
#endif
