// swift-tools-version: 6.0
import PackageDescription

// Staged at .build/ssh-transport-regression so the executable compiles the app's actual transport sources.
let package = Package(
    name: "SSHTransportRegression",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../ios/PiMobileCore"),
        .package(path: "../../ios/.patched-dependencies/Citadel"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.81.0"),
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", exact: "0.3.4"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.12.3"),
    ],
    targets: [
        .executableTarget(
            name: "SSHTransportRegression",
            dependencies: [
                "PiMobileCore",
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
