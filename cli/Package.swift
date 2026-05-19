// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iostesting",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "iostesting", targets: ["iostesting"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        // ObjC bridge over the four MIT-licensed Meta frameworks. Exists because
        // FBSimulatorControl's public headers reference Apple's private SimDevice
        // (from CoreSimulator.framework, which ships without a Clang module map),
        // so Swift can't `import FBSimulatorControl` directly. The bridge imports
        // the FB headers from Objective-C land where SimDevice forward-decls work,
        // and exposes a clean Foundation-only API to Swift.
        .target(
            name: "FBBridge",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .unsafeFlags([
                    "-F", "Frameworks",
                    "-F", "/Library/Developer/PrivateFrameworks",
                    "-fmodules",
                    "-fobjc-arc"
                ])
            ]
        ),
        .executableTarget(
            name: "iostesting",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "FBBridge"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags([
                    "-F", "Frameworks",
                    "-F", "/Library/Developer/PrivateFrameworks",
                    "-Xcc", "-F/Library/Developer/PrivateFrameworks"
                ])
            ],
            linkerSettings: [
                .linkedFramework("FBControlCore"),
                .linkedFramework("FBSimulatorControl"),
                .linkedFramework("FBDeviceControl"),
                .linkedFramework("XCTestBootstrap"),
                .unsafeFlags([
                    "-F", "Frameworks",
                    "-F", "/Library/Developer/PrivateFrameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "@loader_path/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/PrivateFrameworks"
                ])
            ]
        ),
        .testTarget(
            name: "iostestingTests",
            dependencies: ["iostesting"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags([
                    "-F", "Frameworks",
                    "-F", "/Library/Developer/PrivateFrameworks"
                ])
            ]
        )
    ]
)
