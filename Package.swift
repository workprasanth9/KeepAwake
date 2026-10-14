// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeepAwake",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "keepawake", targets: ["keepawake"]),
        .executable(name: "KeepAwakeMenu", targets: ["KeepAwakeMenu"]),
        .library(name: "KeepAwakeCore", targets: ["KeepAwakeCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.5.0"),
    ],
    targets: [
        .target(name: "KeepAwakeCore"),
        .executableTarget(
            name: "keepawake",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "KeepAwakeCore",
            ]
        ),
        .executableTarget(
            name: "KeepAwakeMenu",
            dependencies: ["KeepAwakeCore"]
        ),
        .testTarget(
            name: "KeepAwakeCoreTests",
            dependencies: ["KeepAwakeCore"]
        ),
    ]
)
