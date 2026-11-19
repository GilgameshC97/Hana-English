// swift-tools-version: 6.2

import PackageDescription

// The iOS app itself is built with Hana.xcodeproj. This manifest exposes the
// Foundation-only provider layer (Hana/Providers/Core, also compiled into the
// app target via the synchronized `Hana` group) as a library so it can be
// built and unit-tested with `swift build` / `swift test`, including on Linux CI.
//
// Swift settings mirror the app target (Swift 5 mode, default MainActor
// isolation, approachable concurrency) so isolation errors surface here too.
let appMirrorSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Hana",
    platforms: [.iOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [
        .library(name: "HanaProviderCore", targets: ["HanaProviderCore"]),
    ],
    targets: [
        .target(
            name: "HanaProviderCore",
            path: "Hana/Providers/Core",
            swiftSettings: appMirrorSettings
        ),
        .testTarget(
            name: "HanaProviderCoreTests",
            dependencies: ["HanaProviderCore"],
            path: "Tests/HanaProviderCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: appMirrorSettings
        ),
    ]
)
