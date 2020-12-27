// swift-tools-version:5.3

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
        .target(
            name: "AcknowledgementsGenerator",
            dependencies: []
        ),
    ]
)
