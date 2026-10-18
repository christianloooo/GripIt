// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GripItScannerCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "GripItScannerCore", targets: ["GripItScannerCore"]),
        .executable(name: "GripItScannerCoreChecks", targets: ["GripItScannerCoreChecks"]),
    ],
    targets: [
        .target(
            name: "GripItScannerCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "GripItScannerCoreChecks",
            dependencies: ["GripItScannerCore"]
        ),
        .testTarget(
            name: "GripItScannerCoreTests",
            dependencies: ["GripItScannerCore"]
        ),
    ]
)
