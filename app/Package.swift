// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The Rust core is built by scripts/build-core.sh. Set ERST_CORE_PROFILE to
// "debug" to link target/aarch64-apple-darwin/debug/liberst_ffi.a, or leave it
// unset (or "release") to link the release archive. scripts/check.sh uses
// debug; scripts/build-app.sh uses release.
let coreProfile = ProcessInfo.processInfo.environment["ERST_CORE_PROFILE"] ?? "release"
let coreLibraryDirectory = "\(Context.packageDirectory)/../target/aarch64-apple-darwin/\(coreProfile)"

let package = Package(
    name: "Erst",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Erst", targets: ["ErstApp"]),
    ],
    dependencies: [
        // In-app updates: downloads, verifies the EdDSA signature and the code signature, replaces
        // the app, and relaunches it. Only ErstApp links it.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(
            name: "ErstCoreFFI",
            path: "Sources/ErstCoreFFI",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags(["-L", coreLibraryDirectory]),
                .linkedLibrary("erst_ffi"),
                .linkedFramework("Security"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .target(name: "ErstCore", dependencies: ["ErstCoreFFI"]),
        .target(name: "ErstModel"),
        .target(
            name: "ErstUI",
            dependencies: ["ErstModel"],
            resources: [.process("Resources")]
        ),
        .target(name: "ErstKit", dependencies: ["ErstModel", "ErstCore"]),
        .executableTarget(
            name: "ErstApp",
            dependencies: [
                "ErstModel", "ErstUI", "ErstKit", "ErstCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            // scripts/build-app.sh puts Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .target(name: "ErstPreview", dependencies: ["ErstModel"]),
        // Development tool: renders every screen with preview data to PNG files for review.
        .executableTarget(name: "ErstSnapshots", dependencies: ["ErstModel", "ErstUI", "ErstPreview"]),
        // Development tool: runs the capture pipeline for a few seconds and prints what it kept.
        .executableTarget(name: "ErstProbe", dependencies: ["ErstKit"]),
    ],
    swiftLanguageModes: [.v6]
)
