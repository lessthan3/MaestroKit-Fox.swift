// swift-tools-version: 6.2
// GENERATED — do not edit by hand.
//
// Rendered by scripts/render_package_manifest.sh during a tagged release build
// and committed to the public client SDK repo. Core, Kit, and KMP all ship as
// remote binaryTargets: the url points at the matching GitHub Release asset and
// the checksum is computed from that exact zip, so a resolved package can never
// drift from the binary it was built against.

import PackageDescription

let package = Package(
    name: "MaestroKit",
    platforms: [.tvOS(.v18), .iOS(.v18)],
    products: [
        // MaestroSentryLink and MaestroRiveLink are internal link shims:
        // consumers never import them, but their presence pulls the Sentry and
        // RiveRuntime dependencies into the app so the binary targets resolve.
        .library(name: "MaestroKitFox", targets: ["MaestroKitFox", "MaestroCore", "foxKit", "MaestroSentryLink", "MaestroRiveLink"])
    ],
    dependencies: [
        // Dynamic Sentry product so MaestroCore's `@rpath/Sentry.framework`
        // reference resolves to a single shared copy (no static bake-in, no
        // duplicate-symbol collision with a host app that also uses Sentry).
        .package(url: "https://github.com/getsentry/sentry-cocoa", .upToNextMajor(from: "9.19.1")),
        // RiveRuntime renders MaestroKit's overlays. Pinned to the exact version
        // the shipped binaries were compiled against.
        .package(url: "https://github.com/rive-app/rive-ios", exact: "6.21.0"),
    ],
    targets: [
        .binaryTarget(
            name: "MaestroKitFox",
            url: "https://github.com/lessthan3/MaestroKit-Fox.swift/releases/download/1.12.0/MaestroKitFox.xcframework.zip",
            checksum: "85d45a3ab11b5f4ebe5d9db910abcf370346db6716b09ae3d227be3a16b965cb"
        ),
        .binaryTarget(
            name: "MaestroCore",
            url: "https://github.com/lessthan3/MaestroKit-Fox.swift/releases/download/1.12.0/MaestroCore.xcframework.zip",
            checksum: "d674009ee9103572e4374f79adf473af200bd624fc710b809b9bb7334e870fc3"
        ),
        .binaryTarget(
            name: "foxKit",
            url: "https://github.com/lessthan3/MaestroKit.android/releases/download/foxKit-4.0.37.376/foxKit-4.0.37.376.zip",
            checksum: "1e70c51e75d526eadeb01e65d05fab4486fb7c60c8890704507d03dea7fb3ccc"
        ),
        // Internal link shim (source target): pulls the dynamic Sentry framework
        // into the product so MaestroCore's telemetry resolves at runtime. Its
        // source is committed to the public repo at the path below.
        .target(
            name: "MaestroSentryLink",
            dependencies: [
                .product(name: "Sentry-Dynamic", package: "sentry-cocoa"),
            ],
            path: "Sources/MaestroSentryLink"
        ),
        // Internal link shim (source target): pulls RiveRuntime into the product
        // so the kit binary's `import RiveRuntime` resolves and links. Its source
        // is committed to the public repo at the path below.
        .target(
            name: "MaestroRiveLink",
            dependencies: [
                .product(name: "RiveRuntime", package: "rive-ios"),
            ],
            path: "Sources/MaestroRiveLink"
        )
    ]
)
