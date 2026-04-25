// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "window-manager",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "window-manager",
            targets: ["WindowManager"]
        )
    ],
    targets: [
        .executableTarget(
            name: "WindowManager",
            path: "Sources/WindowManager"
        ),
        .testTarget(
            name: "WindowManagerTests",
            dependencies: ["WindowManager"],
            path: "Tests/WindowManagerTests"
        )
    ]
)

