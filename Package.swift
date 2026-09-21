// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VlogForge",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "VlogForge", targets: ["VlogForge"])],
    targets: [.executableTarget(name: "VlogForge")]
)
