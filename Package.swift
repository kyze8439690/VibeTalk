// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeTalk",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "11.0.0"),
    ],
    targets: [
        .target(
            name: "CWhisper",
            path: "Vendor/CWhisper",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags(["-L", "vendor/lib"]),
                .linkedLibrary("whisper_all"),
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(
            name: "VibeTalk",
            dependencies: [
                "CWhisper",
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
            ],
            path: "Sources/VibeTalk",
            swiftSettings: [
                .unsafeFlags(["-g"], .when(configuration: .release)),
            ]
        ),
    ]
)
