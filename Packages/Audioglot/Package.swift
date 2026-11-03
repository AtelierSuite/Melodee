// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Audioglot",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "Audioglot", targets: ["Audioglot"])
    ],
    dependencies: [
        .package(url: "https://github.com/sbooth/SFBAudioEngine", from: "0.12.1")
    ],
    targets: [
        .target(
            name: "Audioglot",
            dependencies: [
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine")
            ]
        ),
        .testTarget(
            name: "AudioglotTests",
            dependencies: ["Audioglot"]
        )
    ]
)
