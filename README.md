# MaestroKit for Fox

The Maestro SDK for Fox, delivered as a Swift Package. Supports **iOS 18+** and
**tvOS 18+**.

## Install

In Xcode: **File → Add Package Dependencies…**, enter the repository URL, and
choose **Up to Next Major** from the latest version.

```
https://github.com/lessthan3/MaestroKit-Fox.swift
```

Or add it to your own `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/lessthan3/MaestroKit-Fox.swift", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "MaestroKitFox", package: "MaestroKit-Fox.swift"),
        ]
    ),
]
```

Xcode resolves the package and downloads the prebuilt frameworks automatically —
there's nothing else to link or embed.

## Quick start

```swift
import MaestroKitFox

// Once, early in your app's lifecycle:
await MaestroManager.shared.configure(siteID: "YOUR_SITE_ID")
```

Replace `YOUR_SITE_ID` with the site ID your Maestro contact provides.

## Documentation

Integration guides and API reference live in the [`Docs/`](Docs) folder — start
with [`Docs/INTEGRATION.md`](Docs/INTEGRATION.md).

## Release notes

Each version's changes are on the repo's
[Releases](https://github.com/lessthan3/MaestroKit-Fox.swift/releases) page.
