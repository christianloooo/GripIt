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
            resources: [.process("Resources")],
            // The numerical fitter needs optimized loops even when the app is run
            // from Xcode's Debug scheme. Keep all mesh/contact work unchanged.
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
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
