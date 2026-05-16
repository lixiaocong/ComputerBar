// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ComputerBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ComputerBarShared", targets: ["ComputerBarShared"]),
        .executable(name: "ComputerBar", targets: ["ComputerBar"])
    ],
    targets: [
        .target(
            name: "ComputerBarShared"
        ),
        .executableTarget(
            name: "ComputerBar",
            dependencies: ["ComputerBarShared"]
        ),
        .testTarget(
            name: "ComputerBarTests",
            dependencies: ["ComputerBar", "ComputerBarShared"]
        )
    ]
)
