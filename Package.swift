// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Aside",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Aside", targets: ["Aside"])],
    targets: [
        .target(name: "AsideCore"),
        .executableTarget(name: "Aside", dependencies: ["AsideCore"]),
        .testTarget(name: "AsideCoreTests", dependencies: ["AsideCore"])
    ]
)
