// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "minute",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "minute", targets: ["Cards"])
    ],
    targets: [
        .executableTarget(
            name: "Cards",
            path: "Sources/Cards"
        ),
        .testTarget(
            name: "CardsTests",
            dependencies: ["Cards"],
            path: "Tests/CardsTests"
        )
    ]
)
