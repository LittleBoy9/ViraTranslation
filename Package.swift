// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ViraTranslation",
    platforms: [
        .iOS(.v14),
        .macOS(.v12),
        .watchOS(.v7),
        .tvOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ViraTranslation",
            targets: ["ViraTranslation"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        .target(
            name: "ViraTranslation",
            dependencies: [],
            path: "Sources/ViraTranslation"),
        .testTarget(
            name: "ViraTranslationTests",
            dependencies: ["ViraTranslation"],
            path: "Tests/ViraTranslationTests"),
    ],
    swiftLanguageVersions: [.v5]
)

