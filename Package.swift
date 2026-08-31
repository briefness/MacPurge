// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CleanMyMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CleanMyMac", targets: ["CleanMyMac"])
    ],
    targets: [
        .executableTarget(
            name: "CleanMyMac",
            path: "Sources/CleanMyMac"
        ),
        .testTarget(
            name: "CleanMyMacTests",
            dependencies: ["CleanMyMac"],
            path: "Tests/CleanMyMacTests"
        )
    ]
)
