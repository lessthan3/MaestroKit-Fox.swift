// Internal link shim — do NOT import this from consumer code.
//
// MaestroKitFox / MaestroCore ship as prebuilt binary xcframeworks. A binary
// target cannot declare its own package dependencies, so MaestroCore's
// reference to Sentry (`@rpath/Sentry.framework`) would not otherwise pull the
// Sentry runtime into the consuming app.
//
// This tiny source target carries the `Sentry-Dynamic` dependency (see the
// package manifest). Because it is a member of the shipped library product, the
// consumer's app links and embeds the one dynamic `Sentry.framework` that
// MaestroCore resolves at load time — automatically, with no changes to the
// client's own integration or code.
@_exported import Sentry
