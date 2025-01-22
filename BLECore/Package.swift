// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BLECore",
    platforms: [
            .macOS(.v15),
            .iOS(.v18) // Specifies that the minimum iOS version is 13.0
        ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "BLECore",
            targets: ["BLECore"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "BLECore"),
        .testTarget(
            name: "BLECoreTests",
            dependencies: ["BLECore"]
        ),
    ]
)
