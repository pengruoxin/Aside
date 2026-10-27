// swift-tools-version: 5.9
import PackageDescription
import Foundation

let rime = ProcessInfo.processInfo.environment["RIME_PREFIX"] ?? "/opt/homebrew/opt/librime"

let package = Package(
    name: "Aside",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "AsideInputMethod", targets: ["AsideInputMethod"]),
        .executable(name: "AsideInstaller", targets: ["AsideInstaller"])
    ],
    targets: [
        .target(name: "AsideCore"),
        .target(name: "RimeBridge", publicHeadersPath: "include", cSettings: [.unsafeFlags(["-I" + rime + "/include"])], linkerSettings: [.linkedLibrary("rime"), .unsafeFlags(["-L" + rime + "/lib", "-Xlinker", "-rpath", "-Xlinker", rime + "/lib"])]),
        .target(name: "AsideOffline", dependencies: ["AsideCore"]),
        .executableTarget(name: "AsideInputMethod", dependencies: ["AsideCore", "AsideOffline", "RimeBridge"]),
        .executableTarget(name: "AsideInstaller", dependencies: ["AsideOffline", "AsideCore"]),
        .executableTarget(name: "AsideHostHarness", dependencies: ["AsideCore", "AsideOffline"]),
        .testTarget(name: "AsideCoreTests", dependencies: ["AsideCore"])
    ]
)
