// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-srp",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library(name: "SRP", targets: ["SRP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto", from: "1.0.0"),
        .package(url: "https://github.com/adam-fowler/big-num", from: "2.0.0"),
    ],
    targets: [
        .target(name: "SRP", dependencies: ["BigNum", "Crypto"]),
        .testTarget(
            name: "SRPTests", dependencies: ["SRP"]),
    ]
)
