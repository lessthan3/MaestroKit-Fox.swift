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
            url: "https://github.com/lessthan3/MaestroKit-Fox.swift/releases/download/1.15.0/MaestroKitFox.xcframework.zip",
            checksum: "995b4d54530791ac3b1c6542b98dbda2bd2ec9b97ccc907cf023e4d275355007"
        ),
        .binaryTarget(
            name: "MaestroCore",
            url: "https://github.com/lessthan3/MaestroKit-Fox.swift/releases/download/1.15.0/MaestroCore.xcframework.zip",
            checksum: "b317fc7d1cb033b2d9196d7a0e00187c0bf57f2ec7d02f5fe0eb0a835c04a6ff"
        ),
        .binaryTarget(
            name: "foxKit",
            url: "https://github.com/lessthan3/MaestroKit.android/releases/download/foxKit-4.0.42.578/foxKit-4.0.42.578.zip",
            checksum: "a9e731ef55f4ad41bedd74759b39e8d2526351b24e2287ee2a47e4bc5b1a0c2b"
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
