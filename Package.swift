// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LocalDashboard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LocalDashboard",
            path: "Sources/LocalDashboard"
        ),
        .testTarget(
            name: "LocalDashboardTests",
            dependencies: ["LocalDashboard"],
            path: "Tests/LocalDashboardTests"
        )
    ]
)
