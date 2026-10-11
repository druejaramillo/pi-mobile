// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PiMobileCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PiMobileCore", targets: ["PiMobileCore"])],
    targets: [
        .target(name: "PiMobileCore"),
        .testTarget(name: "PiMobileCoreTests", dependencies: ["PiMobileCore"])
    ]
)
