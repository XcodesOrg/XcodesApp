// swift-tools-version:5.4

import PackageDescription

let package = Package(
    name: "AcknowledgementsGenerator",
    platforms: [.macOS(.v11)],
    products: [
        .executable(
            name: "AcknowledgementsGenerator",
            targets: ["AcknowledgementsGenerator"]
        ),
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "AcknowledgementsGenerator",
            dependencies: []
        ),
    ]
)
