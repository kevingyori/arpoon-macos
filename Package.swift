// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Arpoon",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Arpoon", targets: ["Arpoon"])
    ],
    targets: [
        .executableTarget(
            name: "Arpoon",
            path: "Arpoon"
        )
    ]
)
