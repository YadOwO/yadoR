// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReadinessCore",
    platforms: [.iOS("27.0"), .watchOS("27.0"), .macOS(.v15)],
    products: [.library(name: "ReadinessCore", targets: ["ReadinessCore"])],
    targets: [
        .target(name: "ReadinessCore"),
        .testTarget(name: "ReadinessCoreTests", dependencies: ["ReadinessCore"])
    ]
)
