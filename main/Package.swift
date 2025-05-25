// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "App",
    products: [
        .library(
            name: "App", 
            type: .static, 
            targets: ["App"]),
    ],
    dependencies: [
        .package(url: "https://github.com/CmST0us/U8g2Kit", branch: "main", traits: ["Embedded"]),
    ],
    targets: [
		.target(
            name: "App",
            dependencies: [
                "Support",
                .product(name: "U8g2Kit", package: "U8g2Kit"),
                .product(name: "CU8g2", package: "U8g2Kit")],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .enableExperimentalFeature("Embedded"),
            ]),

        .target(name: "Support"),
    ]
)
