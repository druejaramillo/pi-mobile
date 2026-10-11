// swift-tools-version: 6.4
import PackageDescription
import Foundation

// SwiftBuild's Linux cross-linker otherwise records the deployment target as the SDK,
// which keeps native navigation in legacy compatibility styling even on iOS 26.
// Scope the correction to the app so Linux build-tool executables remain unaffected.
let iphoneSDKVersion = ProcessInfo.processInfo.environment["PI_MOBILE_IOS_SDK_VERSION"]
let iphoneSDKLinkerSettings: [LinkerSetting] = iphoneSDKVersion.map { version in
    [.unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "ios",
        "-Xlinker", "17.0", "-Xlinker", version], .when(platforms: [.iOS]))]
} ?? []

// xtool links this library's @main SwiftUI entry into its generated executable.
// The XcodeGen build remains independent of this Linux packaging manifest.
let package = Package(
    name: "PiMobile",
    platforms: [.iOS(.v17)],
    products: [.library(name: "PiMobile", targets: ["PiMobile"])],
    dependencies: [
        .package(path: "PiMobileCore"),
        .package(path: "TailscaleClient"),
        // Same pinned revision plus the checked-in existing-channel event-loop fix, on both build lanes.
        .package(path: ".patched-dependencies/Citadel"),
        // Prepared from the original pin plus the single checked-in manifest patch.
        .package(path: ".xtool-dependencies/SwiftTerm"),
        // Parakeet ASR does not use the optional NeMo TTS text-normalization binary.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "fc8c3e4f5103bf63a242453566525272e143a054", traits: []),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.81.0"),
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", exact: "0.3.4"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.12.3"),
    ],
    targets: [
        .target(
            name: "PiMobile",
            dependencies: [
                "PiMobileCore",
                .product(name: "CTailscale", package: "TailscaleClient"),
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "PiMobile",
            // xtool copies the profile and icon to Bundle.main via xtool.yml.
            exclude: ["Info.plist", "Assets.xcassets", "Resources"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: iphoneSDKLinkerSettings
        ),
    ]
)
