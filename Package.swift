// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RestPilot",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "RestPilot", targets: ["RestPilot"])
    ],
    targets: [
        .executableTarget(
            name: "RestPilot",
            path: "Sources/RestPilot"
        ),
        .testTarget(
            name: "RestPilotTests",
            dependencies: ["RestPilot"],
            path: "Tests/RestPilotTests"
        )
    ]
)
