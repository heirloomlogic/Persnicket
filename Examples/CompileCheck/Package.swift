// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CompileCheck",
    dependencies: [
        .package(name: "Persnicket", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "CompileCheck",
            plugins: [
                .plugin(name: "Persnoop", package: "Persnicket"),
            ]
        )
    ]
)
