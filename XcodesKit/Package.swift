// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let warningsAsErrors: [SwiftSetting] = [
    .unsafeFlags(["-warnings-as-errors"])
]

let swift6Settings: [SwiftSetting] = warningsAsErrors + [
    .swiftLanguageMode(.v6)
]

let package = Package(
    name: "XcodesKit",
    platforms: [.macOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "XcodesKit",
            targets: ["XcodesKit"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/mxcl/Path.swift", from: "1.6.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "XcodesKit",
            dependencies: [
                .product(name: "Path", package: "Path.swift")
            ],
            swiftSettings: swift6Settings),
        .testTarget(
            name: "XcodesKitTests",
            dependencies: ["XcodesKit"],
            swiftSettings: swift6Settings),
    ]
)
