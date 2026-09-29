#if canImport(XcodeProjectPlugin)
import Foundation
import PackagePlugin
import XcodeProjectPlugin

extension Persnipe: XcodeCommandPlugin {
    func performCommand(
        context: XcodePluginContext,
        arguments: [String]
    ) throws {
        let targetNames = try requestedTargetNames(from: arguments)

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
                    throw failure("No target named \"\(name)\" in project \"\(context.xcodeProject.displayName)\".")
                }
                return target
            }
        }

        pinDeveloperDirectory(toXcodeOf: try? context.tool(named: "swift-format").url)
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

        let (launcher, configuration) = try prepareSwiftFormat(
            projectRoot: context.xcodeProject.directoryURL,
            sourceFiles: swiftFilePaths.map { URL(fileURLWithPath: $0) },
            pluginWorkDirectory: context.pluginWorkDirectoryURL
        )

        // One batch for the whole project, chunked only to stay under argument limits:
        // swift-format carries on past a file it can't parse, so a single bad file doesn't
        // stop the rest from being formatted.
        var reportedLines = Set<String>()
        switch format(
            filePaths: swiftFilePaths,
            scope: "project \"\(context.xcodeProject.displayName)\"",
            launcher: launcher,
            configuration: configuration,
            reportedLines: &reportedLines
        ) {
        case .formatted:
            return
        case .failed:
            throw PluginError(message: "swift-format failed; see the error above.")
        case .unusable:
            throw PluginError(message: "Persnipe stopped; see the error above.")
        }
    }
}
#endif
