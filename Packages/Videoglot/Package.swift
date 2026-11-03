// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Videoglot",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "Videoglot", targets: ["Videoglot"])
    ],
    targets: [
        .target(name: "Videoglot"),
        .testTarget(
            name: "VideoglotTests",
            dependencies: ["Videoglot"]
        )
    ]
)
