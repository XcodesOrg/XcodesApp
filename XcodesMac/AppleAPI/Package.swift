// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppleAPI",
    platforms: [.macOS(.v10_13)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "AppleAPI",
            targets: ["AppleAPI"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMajor(from: "6.8.3")),
        .package(name: "PMKFoundation", url: "https://github.com/PromiseKit/Foundation.git", .upToNextMajor(from: "3.3.1")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "AppleAPI",
            dependencies: ["PromiseKit", "PMKFoundation"]),
        .testTarget(
            name: "AppleAPITests",
            dependencies: ["AppleAPI"]),
    ]
)
