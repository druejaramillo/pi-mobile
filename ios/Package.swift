// swift-tools-version: 6.4
import PackageDescription

// xtool links this library's @main SwiftUI entry into its generated executable.
// The XcodeGen build remains independent of this Linux packaging manifest.
let package = Package(
    name: "PiMobile",
    platforms: [.iOS(.v17)],
    products: [.library(name: "PiMobile", targets: ["PiMobile"])],
    dependencies: [
        .package(path: "PiMobileCore"),
        .package(url: "https://github.com/orlandos-nl/Citadel.git", revision: "ae8562f895de06ccb86fdb1cbb65fd99c8976e12"),
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
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
