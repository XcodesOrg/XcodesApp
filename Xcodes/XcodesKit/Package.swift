// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "XcodesKit",
    platforms: [.macOS(.v11)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "XcodesKit",
            targets: ["XcodesKit"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/RobotsAndPencils/AsyncHTTPNetworkService", branch: "main"),
        .package(url: "https://github.com/mxcl/Path.swift", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "XcodesKit",
            dependencies: [
                .product(name: "AsyncNetworkService", package: "AsyncHTTPNetworkService"),
                .product(name: "Path", package: "Path.swift")
            ]),
        .testTarget(
            name: "XcodesKitTests",
            dependencies: ["XcodesKit"]),
    ]
)
