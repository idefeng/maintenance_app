// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MaintenanceApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MaintenanceCore", targets: ["MaintenanceCore"]),
        .executable(name: "MaintenanceApp", targets: ["MaintenanceApp"]),
        .executable(name: "MaintenanceCoreChecks", targets: ["MaintenanceCoreChecks"])
    ],
    targets: [
        .target(name: "MaintenanceCore"),
        .executableTarget(
            name: "MaintenanceApp",
            dependencies: ["MaintenanceCore"]
        ),
        .executableTarget(
            name: "MaintenanceCoreChecks",
            dependencies: ["MaintenanceCore"]
        )
    ]
)
