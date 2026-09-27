// swift-tools-version: 6.0
import PackageDescription

let compileCheckTarget: Target = .executableTarget(
    name: "CompileCheck",
    plugins: [
        .plugin(name: "Persnoop", package: "Persnicket")
    ]
)

let argumentLimitCheckTarget: Target = .target(
    name: "ArgumentLimitCheck",
    plugins: [
        .plugin(name: "Persnoop", package: "Persnicket")
    ]
)

let package = Package(
    name: "CompileCheck",
    dependencies: [
        .package(name: "Persnicket", path: "../..")
    ],
    targets: [compileCheckTarget, argumentLimitCheckTarget]
)
