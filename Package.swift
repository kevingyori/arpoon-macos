// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppHarpoon",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AppHarpoon", targets: ["AppHarpoon"])
    ],
    targets: [
        .executableTarget(
            name: "AppHarpoon",
            path: "AppHarpoon"
        )
    ]
)
