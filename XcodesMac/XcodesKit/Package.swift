// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "XcodesKit",
    platforms: [.macOS(.v10_13)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "XcodesKit",
            targets: ["XcodesKit"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(path: "../AppleAPI"),
        .package(url: "https://github.com/mxcl/Path.swift.git", .upToNextMajor(from: "0.16.0")),
        .package(url: "https://github.com/mxcl/Version.git", .upToNextMajor(from: "2.0.0")),
        .package(url: "https://github.com/mxcl/PromiseKit.git", .upToNextMajor(from: "6.8.3")),
        .package(name: "PMKFoundation", url: "https://github.com/PromiseKit/Foundation.git", .upToNextMajor(from: "3.3.1")),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", .upToNextMajor(from: "2.3.2")),
        .package(url: "https://github.com/mxcl/LegibleError.git", .upToNextMajor(from: "1.0.1")),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", .upToNextMajor(from: "3.2.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "XcodesKit",
            dependencies: ["AppleAPI", .product(name: "Path", package: "Path.swift"), "Version", "PromiseKit", "PMKFoundation", "SwiftSoup", "LegibleError", "KeychainAccess"]),
        .testTarget(
            name: "XcodesKitTests",
            dependencies: ["XcodesKit"]),
    ]
)
