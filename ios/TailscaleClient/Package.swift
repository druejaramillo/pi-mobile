// swift-tools-version: 6.2
import PackageDescription
import Foundation

// Prepared from the pinned upstream Go/C source for the selected build destination.
let archive = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent(".artifacts/library/libtailscale.a").path

let package = Package(
    name: "TailscaleClient",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CTailscale", targets: ["CTailscale"])],
    targets: [
        .target(name: "CTailscale", path: "Sources/CTailscale", publicHeadersPath: "include",
            linkerSettings: [.unsafeFlags([archive]),
                .linkedFramework("CoreFoundation", .when(platforms: [.iOS, .macOS])),
                .linkedFramework("Security", .when(platforms: [.iOS, .macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.iOS, .macOS])),
                .linkedLibrary("resolv", .when(platforms: [.iOS, .macOS]))])
    ]
)
