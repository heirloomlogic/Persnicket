// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CompileCheck",
    dependencies: [
        .package(name: "SwiftFormatPlugin", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "CompileCheck",
            plugins: [
                .plugin(name: "SwiftFormatBuildToolPlugin", package: "SwiftFormatPlugin"),
            ]
        )
    ]
)
