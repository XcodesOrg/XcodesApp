// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let warningsAsErrors: [SwiftSetting] = [
    .unsafeFlags(["-warnings-as-errors"])
]

let package = Package(
    name: "AppleAPI",
    platforms: [.macOS(.v11)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "AppleAPI",
            targets: ["AppleAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/adam-fowler/swift-srp", from: "2.3.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "AppleAPI",
            dependencies: [.product(name: "SRP", package: "swift-srp")],
            swiftSettings: warningsAsErrors),
        .testTarget(
            name: "AppleAPITests",
            dependencies: ["AppleAPI"],
            swiftSettings: warningsAsErrors),
    ]
)
