// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Harpoon",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Harpoon", targets: ["Harpoon"])
    ],
    targets: [
        .executableTarget(
            name: "Harpoon",
            path: "Harpoon"
        )
    ]
)
