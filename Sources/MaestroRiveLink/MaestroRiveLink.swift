// Internal link shim — do NOT import this from consumer code.
//
// MaestroKitFox ships as a prebuilt binary xcframework whose source imports
// RiveRuntime. A binary target cannot declare its own package dependencies, so
// the consumer's package graph would have no RiveRuntime to resolve or link
// against — `swift build` fails with "unable to resolve module dependency:
// 'RiveRuntime'".
//
// This tiny source target carries the RiveRuntime dependency (see the package
// manifest). Because it is a member of the shipped library product, RiveRuntime
// resolves and links into the consuming app automatically — no changes to the
// client's own integration or code.
@_exported import RiveRuntime
