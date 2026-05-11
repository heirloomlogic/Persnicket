// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Persnicket",
    products: [
        .plugin(
            name: "Persnoop",
            targets: ["Persnoop"]
        ),
        .plugin(
            name: "Persnipe",
            targets: ["Persnipe"]
        ),
    ],
    targets: [
        .plugin(
            name: "Persnoop",
            capability: .buildTool()
        ),
        .plugin(
            name: "Persnipe",
            capability: .command(
                intent: .sourceCodeFormatting(),
                permissions: [
                    .writeToPackageDirectory(reason: "Format Swift source files in-place.")
                ]
            )
        ),
    ]
)
