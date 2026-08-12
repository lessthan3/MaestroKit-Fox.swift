# Fox Integration Guide — MaestroKitFox (Swift / iOS & tvOS)

This guide walks the Fox client app through integrating **MaestroKitFox** end-to-end: install, configure, wire the event delegate, present the panel, push player state, apply panel overrides, render overlays, and handle every edge case the SDK can throw at the host.

---

## Table of Contents

1. [Requirements](#1-requirements)
2. [Installation](#2-installation)
3. [Configuration at app launch](#3-configuration-at-app-launch)
4. [Implementing the event delegate](#4-implementing-the-event-delegate)
5. [Starting and stopping an event](#5-starting-and-stopping-an-event)
6. [Pushing player state into the SDK](#6-pushing-player-state-into-the-sdk)
7. [Presenting the Maestro panel](#7-presenting-the-maestro-panel)
8. [Rendering overlays](#8-rendering-overlays)
9. [Panel data overrides (per-panel API config)](#9-panel-data-overrides-per-panel-api-config)
10. [Multiview lifecycle and clip-return flow](#10-multiview-lifecycle-and-clip-return-flow)
11. [Key plays lifecycle](#11-key-plays-lifecycle)
12. [Stats configuration](#12-stats-configuration)
13. [Analytics](#13-analytics)
14. [Reference: public types](#14-reference-public-types)
15. [Edge cases & gotchas](#15-edge-cases--gotchas)
16. [Troubleshooting checklist](#16-troubleshooting-checklist)
17. [Appendix: minimal end-to-end example](#appendix-minimal-end-to-end-example)

---

## 1. Requirements

| Target          | Minimum |
|---|---|
| iOS deployment  | 18.0    |
| tvOS deployment | 18.0    |
| Swift           | 6.2     |
| Xcode           | 16+     |

MaestroKitFox is shipped as an XCFramework via a Swift Package.

---

## 2. Installation

### Swift Package Manager

Add the **MaestroKitFox** Swift Package to your Xcode project (File → Add Package Dependencies…) using the URL provided by the Maestro team.

In your app target, import:

```swift
import MaestroKitFox
```

That single import is all you need — every public type referenced in this guide is available from `MaestroKitFox`.

### Fonts

MaestroKitFox's UI renders in the Fox brand fonts (`FOXONEAero*`, `FOXONEAeroCnd*`, `VenuAero*`), referenced by **PostScript name** (e.g. `FOXONEAero-400-Regular`, `VenuAero-Bold`). The SDK does **not** bundle or register these fonts — **your app must ship and register them** so they are available process-wide, via the standard `UIAppFonts` `Info.plist` entry or your own `CTFontManager` registration at launch. A Fox app already registers its brand fonts, so typically there is nothing new to add — just confirm the PostScript names match the list above. Any face that isn't registered falls back to the system font.

---

## 3. Configuration at app launch

Call `configure` once, as early as possible (typically in your `App`'s `init` or your scene's bootstrap).

```swift
import MaestroKitFox

@main
struct FoxApp: App {
    init() {
        Task {
            await MaestroManager.shared.configure(
                siteID: "fox-prod-site-id",
                showHelloWorld: false,                 // debug-only; leave false in prod
                maestroWorkingEnvironment: .prod       // .test | .qa | .prod
            )
        }
    }
    // …
}
```

### Notes

- `MaestroManager.shared` is an **actor**. Every method is `async`.
- `configure` is idempotent — calling it again just overwrites the cached site ID and `showHelloWorld` flag.
- `showHelloWorld: true` enables a built-in placeholder overlay used during onboarding/QA. Keep it off in production.

---

## 4. Implementing the event delegate

The delegate is the SDK's only way to talk back to your app. Implement `MaestroEventDelegate` (the Fox extension), which adds Fox-specific callbacks on top of the base lifecycle methods.

```swift
import MaestroKitFox
import SwiftUI

@MainActor
final class FoxMaestroDelegate: MaestroEventDelegate {
    typealias MaestroOverlayEvent = MaestroKitFox.MaestroOverlayEvent

    weak var host: FoxPlayerHost?   // your player coordinator / view model

    // MARK: - Base lifecycle

    // Legacy Core-protocol requirements. The Fox key-plays path is id-based via
    // `onKeyPlaySelected` (see §11); these are inherited stubs. Key-plays fetch and
    // retry are SDK-internal, so `userRequestedNewKeyPlaysData` is typically a no-op.
    // `playClip(atIndex:)` may still fire in one edge case — see §15.9.
    func userRequestedNewKeyPlaysData() { }

    func playClip(atIndex index: Int) {
        // No-op unless you also support the legacy index flow; guard on host teardown (§15.9).
    }

    func shouldShowPanel() {
        host?.presentMaestroPanel()
    }

    func shouldHidePanel() {
        host?.dismissMaestroPanel()
    }

    func shouldShowOverlay(event: MaestroOverlayEvent) async {
        await host?.presentOverlay(event)
    }

    func shouldHideOverlay() async {
        await host?.dismissOverlay()
    }

    func trackAction(analytics: [String: String]) {
        host?.analytics.track(action: analytics)
    }

    func trackImpression(analytics: [String: String]) {
        host?.analytics.trackImpression(analytics)
    }

    func playPauseButtonPressed() {
        host?.togglePlayback()
    }

    // MARK: - Fox callbacks

    func onKeyPlaySelected(event: KeyPlayClipInfo) {
        host?.handleKeyPlaySelection(event)
    }

    func onNewMultiview(event: NewMultiviewEvent) {
        // The SDK switched to a multiview layout. Update the player to the new event set.
        let listingIds = event.childListings.map(\.listingId)
        host?.maestroInterface?.updateEventData(eventIDs: listingIds)
        host?.renderMultiviewLayout(event)
    }

    func onKeyPlayListChanged(keyPlays: [KeyPlayClipInfo]) {
        host?.keyPlays = keyPlays
    }

    func onNewSingleStream(event: NewSingleStreamEvent) {
        // Multiview collapsed back to one stream. Switch the player to it.
        host?.maestroInterface?.updateEventData(eventIDs: [event.listingId])
        host?.collapseToSingleStream(event)
    }

    func onPanelEvent(event: any PanelEvent) {
        // Fires when a panel API responds 401. Use it to refresh tokens and re-apply overrides.
        host?.handlePanelAuthFailure(event)
    }
}
```

### Critical lifecycle rule

`MaestroManager` **holds the delegate weakly.** You must retain it yourself (typically on your view model or app coordinator). If the delegate deallocates, all callbacks silently stop.

---

## 5. Starting and stopping an event

```swift
// 1. Assign the delegate. The setter is safe to call from a synchronous context.
MaestroManager.shared.delegate = myDelegate

// 2. Start watching.
let interface: any MaestroEventInterface =
    await MaestroManager.shared.userDidStartWatchingEvents(eventIDs: ["evt-12345"])

// 3. Hold onto `interface` — you'll call back into it from your player.
host.maestroInterface = interface

// 4. End the event when the player closes.
await MaestroManager.shared.userDidStopWatchingEvents(["evt-12345"])
host.maestroInterface = nil
```

### Single vs. multi-event start

```swift
// Single event:
await MaestroManager.shared.userDidStartWatchingEvents(eventIDs: ["evt-12345"])

// Multiview (or pre-seeded children):
await MaestroManager.shared.userDidStartWatchingEvents(
    eventIDs: ["evt-parent", "evt-child-1", "evt-child-2"]
)
```

Deprecated singular forms (`userDidStartWatchingEvent(eventID:)`, `userDidStopWatchingEvent(_:)`) still work but emit warnings — prefer the plural variants.

### Re-starting an event

Calling `userDidStartWatchingEvents` while another event is active is **safe**: the manager detaches the previous instance, destroys its presenters (multiview, key plays, stats, overlay), and creates a fresh one. You do **not** need to call `userDidStopWatchingEvents` first. See §15.3.

---

## 6. Pushing player state into the SDK

`MaestroEventInterface` is your one-way pipe from the host player → SDK. All calls are `@MainActor`.

```swift
// Timecode — called continuously by your player (every 250–1000ms is typical).
// The value is UTC epoch milliseconds (wall-clock), not player playback offset —
// KMP compares it against `KeyPlayItem.startTimeMs` for no-spoiler filtering.
interface.updatePlayerTimeCode(timeCode: Date().timeIntervalSince1970 * 1000)

// Notify the SDK when your player handles its UI events:
interface.didShowPanel()       // confirm `shouldShowPanel()`
interface.didHidePanel()       // confirm `shouldHidePanel()`

// Key-play clip playback (the SDK's progress UI is driven by these). Id-based —
// use the listingId + keyPlayId from the `onKeyPlaySelected` event. Report
// `progress: nil` when the clip ends; it also triggers the multiview restore
// (see §10 and §11):
interface.updateKeyPlayProgress(eventId: event.listingId, keyPlayId: event.keyPlayId, progress: 0.42)
interface.updateKeyPlayProgress(eventId: event.listingId, keyPlayId: event.keyPlayId, progress: nil)

// Replace the event-id set (multiview transitions, manual switches, etc.):
interface.updateEventData(eventIDs: ["evt-new-listing"])

// Read back what the SDK currently believes the event set is:
let current: [String]? = interface.getCurrentEventIDs()
```

Send **timecode in UTC epoch milliseconds** (wall-clock time, not player playback offset).

---

## 7. Presenting the Maestro panel

`MaestroPanel` is a SwiftUI view. Drop it into whichever side-rail / sheet container your player uses.

```swift
import MaestroKitFox

struct PlayerScreen: View {
    @State private var showPanel = false

    var body: some View {
        HStack(spacing: 0) {
            VideoPlayerLayer()
            if showPanel {
                MaestroPanel(width: 453)             // pass nil for flex width
                    .transition(.move(edge: .trailing))
            }
        }
        .onReceive(panelVisibilityPublisher) { visible in
            showPanel = visible
            // Confirm to the SDK after the transition lands.
            if visible { host.maestroInterface?.didShowPanel() }
            else { host.maestroInterface?.didHidePanel() }
        }
    }
}
```

### Panel show/hide contract

| Step | Who acts | Method |
|---|---|---|
| 1 | SDK requests | `shouldShowPanel()` on your delegate |
| 2 | App presents `MaestroPanel` | (your UI) |
| 3 | App confirms | `interface.didShowPanel()` |
| 4 | SDK requests | `shouldHidePanel()` on your delegate |
| 5 | App dismisses | (your UI) |
| 6 | App confirms | `interface.didHidePanel()` |

Skipping the confirmation steps causes the SDK's internal "panel is visible" state to drift; overlay timing depends on it.

### Collapsing header — sticky panel (iOS / iPad)

For a portrait layout where the video stays fixed and the panel scrolls beneath it, use the `collapsingHeader` initializer. The panel hosts itself in a single scroll: your header scrolls away, the tab bar pins to the top, and the selected tab's content flows in the same scroll — one continuous gesture.

```swift
VStack(spacing: 0) {
    VideoPlayerLayer()                 // fixed at the top
        .aspectRatio(16/9, contentMode: .fit)

    MaestroPanel {                     // fills the space below; owns its scroll
        EventMetadataView()            // your content — collapses as the user scrolls
    }
}
```

Put whatever you want to collapse (title, matchup, score, controls) in the `collapsingHeader` closure. The panel handles the collapse, the pinned tab bar, resetting a newly-selected tab to its top, and short/empty tabs — no host code.

Rules:

- **Do not wrap this panel in your own `ScrollView`.** `MaestroPanel { … }` *is* a scroll view. Nesting it inside another scroll gives you two competing scroll containers: the panel renders with no bounded height, the tab bar pins to the panel's own scroll (not under your video), and the collapse logic misfires. If your reason for an outer scroll is "header content that should scroll away," that content belongs in `collapsingHeader` instead — then you don't need an outer scroll at all.
- **Place it in a `VStack` below your fixed content.** It's a greedy vertical scroll and fills the remaining height; its tab bar pins to the top of that region.
- **Let the header size itself.** Its height is measured to find the collapse point — give it natural intrinsic height, don't force `maxHeight: .infinity`.
- **This is an iOS / iPad affordance.** For a side-by-side rail or on tvOS, use the plain `MaestroPanel(width:)` (no closure).

If you genuinely need your own outer scroll — arbitrary host content scrolling *around* the panel (a feed, related videos) — then the panel can't also be the collapsing/pinning surface. Use the classic `MaestroPanel(width:)` with an explicit `.frame(height:)` so it sits as one bounded, self-contained item and scrolls internally. The collapsing-header and host-owns-the-scroll layouts are mutually exclusive.

### tvOS focus

`MaestroPanel` already wraps itself in a focus section. Make sure your host view doesn't trap focus on a sibling — wrap the rest of your screen in its own focus section.

---

## 8. Rendering overlays

When the SDK wants an overlay surfaced, it calls `shouldShowOverlay(event:)` on your delegate with a `MaestroOverlayEvent`. The simplest integration is to hand the event straight to the bundled `MaestroOverlay` SwiftUI view:

```swift
import MaestroKitFox

struct OverlayLayer: View {
    let event: MaestroOverlayEvent?

    var body: some View {
        if let event {
            MaestroOverlay(
                event: event,
                dismissTimeoutSeconds: 5.0,
                onOverlayClicked: { /* analytics, deep-link, etc. */ },
                onOverlayFinished: { /* clear local state */ }
            )
        }
    }
}
```

```swift
func shouldShowOverlay(event: MaestroOverlayEvent) async {
    host?.currentOverlay = event
}

func shouldHideOverlay() async {
    host?.currentOverlay = nil
}
```

### Public surface of `MaestroOverlayEvent`

| Property | Type | Notes |
|---|---|---|
| `id`     | `String` | Stable identifier. Use it for `Identifiable` view recreation. |
| `size`   | `CGSize` | Recommended render size in points. |

The event is **opaque** beyond `id` and `size`. Pass it to `MaestroOverlay` and let the framework render it.

### `MaestroOverlay` parameters

| Parameter | Default | Purpose |
|---|---|---|
| `event` | — | The event from `shouldShowOverlay(event:)`. |
| `dismissTimeoutSeconds` | `5.0` | Auto-dismiss after this long. |
| `onOverlayClicked` | `nil` | Called when the user activates the overlay (tap / Siri remote select). |
| `onOverlayFinished` | `nil` | Called after the overlay finishes (timeout or user click). |
| `maestroManager` | `.shared` | Override only for advanced testing. |

For the full overlay implementation guide — pipeline, lifecycle, tap handling, QA helpers,
and gotchas — see **[OVERLAYS.md](OVERLAYS.md)**.

---

## 9. Panel data overrides (per-panel API config)

Each panel (Multiview, Key Plays, Stats) gets its data from an HTTP endpoint that the **client app must configure per event**. There are two ways:

### 9a. Typed convenience setters (preferred)

```swift
let mgr = MaestroManager.shared

// Multiview product API
await mgr.setProductAPIConfig(
    url: "https://api.fox.com/multiview/products/evt-12345",
    method: "GET",
    headers: ["Authorization": "Bearer \(token)"],
    refreshIntervalMs: 30_000
)

// Multiview backend (token-bearing; baseUrl optional — omit to use the SDK default)
await mgr.setMultiViewAPIConfig(
    overrideBaseUrl: nil,
    token: bearerToken
)

// Key Plays
mgr.setKeyPlaysAPIConfig(
    url: "https://api.fox.com/keyplays/evt-12345",
    method: "GET",
    headers: ["Authorization": "Bearer \(token)"]
)

// Stats
mgr.setStatsAPIConfig(
    baseUrl: "https://stats.fox.com",
    paths: [
        "matchTimeline": "/v1/match/{eventId}/timeline",
        "teamStats":     "/v1/match/{eventId}/teamStats"
    ],
    method: "GET",
    headers: ["Authorization": "Bearer \(token)"]
)
```

### 9b. Generic structured overrides

Use this when override values arrive as JSON from a remote config service (CDN, feature-flag, internal config).

```swift
let multiviewProductRequest = """
{
  "Url": "https://api.fox.com/multiview/products/evt-12345",
  "Method": "GET",
  "Headers": {"Authorization": "Bearer abc"},
  "RefreshIntervalMs": 30000
}
"""

let overrides: [MaestroPanelOverride] = [
    .init(panelIdentifier: "foxMultiview", interfaceName: "productAPIRequest", overrideValue: multiviewProductRequest),
    .init(panelIdentifier: "foxMultiview", interfaceName: "multiViewAPIConfig", overrideValue: #"{"accessToken":"\#(token)"}"#),
    .init(panelIdentifier: "foxKeyPlays",  interfaceName: "productAPIRequest", overrideValue: keyPlaysRequestJSON)
]

let results = await MaestroManager.shared.setDataToPanels(overrides)
for (override, result) in zip(overrides, results) {
    if case .failure(let error) = result {
        log.error("override for \(override.panelIdentifier).\(override.interfaceName) failed: \(error.description)")
    }
}
```

### Supported `(panelIdentifier, interfaceName)` pairs

| `panelIdentifier` | `interfaceName`        | `overrideValue` JSON schema |
|---|---|---|
| `foxMultiview`    | `productAPIRequest`    | `{ Url, Method?, Headers?, RefreshIntervalMs? }` |
| `foxMultiview`    | `multiViewAPIConfig`   | `{ overrideBaseUrl?, accessToken }` |
| `foxMultiview`    | `childListings`        | `["listing-1", "listing-2", …]` (JSON array of listing IDs) |
| `foxKeyPlays`     | `productAPIRequest`    | `{ Url, Method?, Headers?, RefreshIntervalMs? }` |

For type-safe constants, use:

- `FoxMultiviewPanelOverrideInterfaces` (`.productAPIRequest`, `.multiViewAPIConfig`, `.childListings`)
- `FoxKeyPlaysPanelOverrideInterfaces` (`.productAPIRequest`)

Anything else returns `.failure(.unsupportedPanelIdentifier(...))` or `.failure(.interfaceUnsupported(...))`.

### Error model — `MaestroPanelOverrideError`

| Case | Meaning | What to do |
|---|---|---|
| `.noActiveEvent` | `userDidStartWatchingEvents` hasn't been called. | Start the event first, then re-apply. |
| `.unsupportedPanelIdentifier(String)` | Panel name unknown to the kit. | Use exactly `foxStats` / `foxKeyPlays` / `foxMultiview`. |
| `.interfaceUnsupported(String)` | Interface name unknown for that panel. | Use the matrix above. |
| `.emptyOverrideValue` | Override string was empty. | Always send at least `{}`. |
| `.invalidOverrideValue(String)` | JSON did not decode into the expected shape. | Validate JSON; check required keys (`Url`, `accessToken`). |
| `.panelNotConfigured(String)` | Panel exists but has no live presenter yet. | Wait until the event is fully started, or re-apply on `onPanelEvent`. |
| `.unknown` | Reserved. | File a bug. |

---

## 10. Multiview lifecycle and clip-return flow

### Switching into multiview

When the user picks a curated multiview or layout, the SDK fires `onNewMultiview(event:)`. Use the event to:

1. If any listingId in `event.childListings` is not yet in your stats `paths` map, resolve its `sportEventURI` and re-call `setStatsAPIConfig` with the cumulative map (see §12). Do this **before** step 2.
2. Tell the SDK which streams you're now playing: `interface.updateEventData(eventIDs: event.childListings.map(\.listingId))`.
3. Lay out your video tiles using `event.childListings[i].position` (center-based, normalized `0…1`, with **Y origin at the bottom**). Convert to your UI's coordinate system.
4. Cache `event.multiviewId` if you want to display its name.

`setKeyPlaysAPIConfig`, `setProductAPIConfig`, and `setMultiViewAPIConfig` do **not** need to be re-called on layout switch — only `setStatsAPIConfig`, and only if new listingIds appeared.

### Snapshot / restore for key-play interludes

When a user taps a key play during multiview, the clip plays in a single-stream
view and then returns. So the user lands back on the exact layout (and Showcase
spotlight) they left, the SDK snapshots the multiview before the interlude and
restores it after.

**In the standard flow this is automatic — you do not call anything:**

- When a key play is selected through the SDK's key-plays panel, the SDK
  snapshots the current multiview for you.
- When you report the clip has ended with `updateKeyPlayProgress(..., progress: nil)`
  (see §11), the SDK restores it.

**Manual calls (escape hatch).** Only if you present key plays through your **own**
UI — bypassing the SDK's key-plays panel — is the auto-snapshot not taken, and you
must capture it yourself before playback:

```swift
// Before navigating away to play the clip (only if not using the SDK panel):
await MaestroManager.shared.snapshotCurrentMultiview()

// Optional — restore also fires on `updateKeyPlayProgress(progress: nil)`:
await MaestroManager.shared.restoreMultiviewIfNeeded()
```

`snapshotCurrentMultiview` records whichever curated multiview or layout is
currently selected (including its spotlight pick). `restoreMultiviewIfNeeded` is a
**no-op** if no snapshot exists.

### Collapsing back to a single stream

When the user closes the multiview, `onNewSingleStream(event:)` fires. Call `interface.updateEventData(eventIDs: [event.listingId])` and tear down any layout UI on your side.

### Checking active state

```swift
let active = await MaestroManager.shared.isMultiviewActive()
```

`true` iff a curated or custom layout is selected on screen — useful for gating cross-feature interactions.

### Multiview onboarding overlay

The SDK shows a one-time onboarding overlay the first time a user opens multiview. Reset for QA via:

```swift
await MaestroManager.shared.resetMultiviewOverlay()
```

---

## 11. Key plays lifecycle

Key plays are **id-based**, not index-based. The SDK identifies a clip by its
`listingId` + `keyPlayId` (delivered on `KeyPlayClipInfo`), and you report
playback with `updateKeyPlayProgress(eventId:keyPlayId:progress:)`. There is no
`playClip(atIndex:)` / `did*Clip(atIndex:)` flow on the Fox delegate.

### Flow

1. SDK fetches key plays from the URL configured via `setKeyPlaysAPIConfig` (or the `foxKeyPlays.productAPIRequest` override).
2. List changes → `onKeyPlayListChanged(keyPlays: [KeyPlayClipInfo])` fires on the delegate.
3. User selects one → `onKeyPlaySelected(event: KeyPlayClipInfo)` fires. `event.listingId` and `event.keyPlayId` identify the clip.
4. Play the clip in your player. The clip is an interlude away from the current view; the SDK snapshots the multiview automatically so it can be restored when the clip ends — no host call needed for the standard panel flow. (Only a fully custom key-plays UI must snapshot itself — see §10, "Snapshot / restore for key-play interludes".)
5. As the clip plays, report progress `0.0 → 1.0`:

   ```swift
   interface.updateKeyPlayProgress(
       eventId: event.listingId,
       keyPlayId: event.keyPlayId,
       progress: fraction   // 0.0 … 1.0
   )
   ```
6. When the clip **finishes** (or your player tears it down), send `progress: nil`:

   ```swift
   interface.updateKeyPlayProgress(
       eventId: event.listingId,
       keyPlayId: event.keyPlayId,
       progress: nil
   )
   ```

### `progress: nil` is the clip-end signal

`progress: nil` is not just "no progress" — it is the **end-of-clip** signal, and
it drives the return to multiview. On `nil` the SDK calls
`restoreMultiviewIfNeeded()`, returning the user to the layout (and Showcase
spotlight) captured before the interlude. Send it exactly once when the clip
ends; sending it early cuts the clip short by restoring the multiview mid-play.
Restore is a no-op if no snapshot was captured, so it is always safe to send.

> Drive `nil` off your player's real completion/teardown, **not** a fixed timer.
> The panel's on-screen progress bar is UI-only and may finish before a longer
> host clip does.

### Error / retry

The SDK fetches and retries key plays itself against the endpoint configured via
`setKeyPlaysAPIConfig` (or the `foxKeyPlays.productAPIRequest` override) — the
"Try Again" affordance in the panel re-requests that endpoint. There is no
host-supplied index or `updateKeyPlaysData` callback in the Fox integration.

---

## 12. Stats configuration

Stats panels (Goal Matrix, Game Momentum, Match Timeline, Team Stats, Expected vs Scored Goals) read from one base URL plus a `paths` dictionary **keyed by `listingId`**, where each value is the sport-event path suffix (the `sportEventURI`) appended to `baseUrl` when the SDK queries stats for that listing.

```swift
mgr.setStatsAPIConfig(
    baseUrl: "https://stats.fox.com/v1/main/events/components/",
    paths: [
        "<LISTING_ID_A>": "soccer/<competition>/events/<sportEventId>",
        "<LISTING_ID_B>": "soccer/<competition>/events/<otherSportEventId>",
        "<LISTING_ID_C>": "soccer/<competition>/events/<otherSportEventId>"  // two listings can share one event
    ],
    method: "GET",
    headers: ["x-fox-apikey": apiKey]
)
```

At fetch time, the SDK looks up the active listingId(s) in `paths` and appends the value to `baseUrl`. A listingId with no entry in `paths` produces no stats request — the stats panel renders empty for that listing.

### Lifecycle — when to call

Unlike `setKeyPlaysAPIConfig` (a single URL) and `setProductAPIConfig` / `setMultiViewAPIConfig` (event-session scope), `setStatsAPIConfig` is **per-listing** and must be re-applied whenever a layout change introduces listingIds not in the current map. Three patterns are valid:

1. **Pre-populate everything up front.** If you know every listingId that could possibly appear (single stream + every curated MV's children), pass them all in the initial call and never re-call. Simplest, but doesn't fit build-your-own-MV.
2. **Re-call on layout switch (cumulative).** Maintain a `[listingId: sportEventURI]` map on your side. In `onNewMultiview` / `onNewSingleStream`, append any new listingIds' URIs to the map, then call `setStatsAPIConfig` **before** `interface.updateEventData(eventIDs:)`. Always pass the cumulative map — `setStatsAPIConfig` **replaces** the config, it does not merge.
3. **Always re-call defensively.** Same as (2) but called on every switch regardless of whether the IDs are new. Safe as long as you always pass the cumulative map and apply before `updateEventData`.

### Resolving `sportEventURI` for new listings

The SDK does not surface a `sportEventURI` field on `childListings` and does not fetch URIs on your behalf. You must obtain them yourself — typically from your own catalog/backend, keyed by listingId — and feed them into `paths`.

---

## 13. Analytics

The SDK never makes analytics calls itself — every action and impression is dispatched via the delegate:

```swift
func trackAction(analytics: [String: String])      // fired on user actions
func trackImpression(analytics: [String: String])  // fired when surfaces appear
```

The dictionary keys are stable. Forward them verbatim to your analytics SDK (Segment, Adobe, etc.) — do not transform.

For debugging the SDK itself (panel selection, overlay lifecycle, KMP state transitions, presenter startup), enable console logging with `await MaestroManager.shared.setConsoleLoggingEnabled(true)`. See **[LOGGING.md](LOGGING.md)**.

---

## 14. Reference: public types

| Type | Used for |
|---|---|
| `MaestroManager` | The actor singleton you talk to. Access via `MaestroManager.shared`. |
| `MaestroPanel` | SwiftUI view rendering the Maestro side panel. |
| `MaestroOverlay` | SwiftUI view that renders a `MaestroOverlayEvent`. |
| `MaestroPanelType` | `.stats` / `.keyPlays` / `.multiview` — backed by `foxStats`, `foxKeyPlays`, `foxMultiview`. |
| `MaestroOverlayEvent` | Overlay payload passed to `shouldShowOverlay`. Public surface: `id`, `size`. |
| `MaestroEventDelegate` | Protocol your app implements (Fox extension — adds `onKeyPlaySelected`, `onNewMultiview`, `onKeyPlayListChanged`, `onNewSingleStream`, `onPanelEvent`). |
| `MaestroEventInterface` | Protocol the SDK returns from `userDidStartWatchingEvents`. Your one-way push channel. |
| `MaestroPanelOverride` | Struct for generic overrides. |
| `MaestroPanelOverrideError` | Error cases returned by `setDataToPanel`. |
| `MaestroWorkingEnvironment` | `.test` / `.qa` / `.prod`. |
| `FoxMultiviewPanelOverrideInterfaces` | Enum of override interface names for multiview. |
| `FoxKeyPlaysPanelOverrideInterfaces` | Enum of override interface names for key plays. |
| `KeyPlayClipInfo` | Clip metadata delivered by `onKeyPlaySelected` / `onKeyPlayListChanged`. Key fields: `listingId`, `keyPlayId` — pass these to `updateKeyPlayProgress`. |
| `KeyPlayProgress` | Progress payload sent to KMP by `updateKeyPlayProgress(eventId:keyPlayId:progress:)`: `listingId`, `keyPlayId`, `progress`. |
| `NewMultiviewEvent` | Multiview switch payload. |
| `NewSingleStreamEvent` | Single-stream switch payload. |
| `PanelEvent` | Lifecycle event delivered to `onPanelEvent`. Fires today on 401-Unauthorized API responses. |

---

## 15. Edge cases & gotchas

### 15.1 The delegate is held weakly

`MaestroManager` keeps the delegate as a `weak` reference. If you write:

```swift
MaestroManager.shared.delegate = FoxMaestroDelegate()   // ❌ deallocates immediately
```

…you'll get zero callbacks. Always retain the delegate on a long-lived object (App, AppDelegate, view model).

### 15.2 `MaestroManager` is an actor

Direct property reads from non-isolated contexts require `await`. The `delegate` setter is assignable from sync code, but anything that touches actor state goes through async.

### 15.3 Re-starting an event without stopping the previous one

Supported and idempotent. The manager detaches the prior instance, destroys its presenters, and creates a new instance. However:

- **Pending Tasks** that captured the old `MaestroEventInterface` will silently no-op against the detached instance — cancel them yourself if they hold resources.
- The current overlay is finalized before swap — your `shouldHideOverlay` will fire one last time.
- All panel overrides applied to the old instance are **lost**. Re-apply them after restart.

### 15.4 Calling SDK methods before `configure`

If `configure` has not been awaited, `userDidStartWatchingEvents` returns a no-op interface. All subsequent calls on it become no-ops. **Always `await configure` before starting an event.**

### 15.5 401 Unauthorized from a panel API

The SDK does **not** retry on its own. It fires `onPanelEvent(event:)` on your delegate. Implement a token-refresh + re-apply pattern:

```swift
func onPanelEvent(event: any PanelEvent) {
    Task {
        let freshToken = try await auth.refresh()
        await MaestroManager.shared.setMultiViewAPIConfig(token: freshToken)
        // Re-apply other panels too if they share the token.
    }
}
```

### 15.6 Empty event IDs

`userDidStartWatchingEvents(eventIDs: [])` is **not validated** by the SDK. Don't pass an empty array — panels will render empty states. Guard upstream.

### 15.7 tvOS focus

`MaestroPanel` manages its own focus section. Wrap your player UI in a sibling focus section so focus can move between them cleanly. Avoid trapping focus on your video layer with `.focusable()` unless your player explicitly needs it.

### 15.8 Mobile (iOS) — width

Below ~360pt some Stats subviews start to clip. Give `MaestroPanel` at least that much width on iPhone, or use `MaestroPanel(width: nil)` and let it expand to fill.

Presenting the collapsing-header panel (`MaestroPanel { … }`) inside your own `ScrollView` renders it empty/broken — it already owns a scroll. See §7 "Collapsing header": put collapsing content in the header closure, or use `MaestroPanel(width:)` with a fixed height if you need an outer host scroll.

### 15.9 `playClip(atIndex:)` after `userDidStopWatchingEvents`

The SDK may dispatch one last `playClip` if the user tapped right before stop. Ignore it if `host.maestroInterface == nil`.

### 15.10 Fonts not appearing

The kit registers Fox fonts inside `MaestroManager.init`. If your UI renders before `MaestroManager.shared` is touched, fonts default to system. Access `MaestroManager.shared` once at launch — even just `_ = MaestroManager.shared` — to force registration.

### 15.11 Snapshot before clip, restore after

If you skip `snapshotCurrentMultiview()` before navigating to a key-play clip, `restoreMultiviewIfNeeded()` does nothing. You will return the user to a single stream rather than the layout they came from. Always pair the two.

### 15.12 The `childListings` override

Passing `childListings` as a structured override is currently parsed and accepted but does not yet feed the multiview presenter — it is reserved. Don't depend on its side effects.

### 15.13 Updating timecode

`updatePlayerTimeCode(timeCode:)` expects **UTC epoch milliseconds as a `Double`** (e.g. `Date().timeIntervalSince1970 * 1000`). Passing seconds will make every time-gated overlay fire either far too early or never.

### 15.14 Detached interface after stop

After `userDidStopWatchingEvents`, the `MaestroEventInterface` you held becomes a no-op shell. Calls don't throw — they're silently dropped. Re-acquire by calling `userDidStartWatchingEvents` again.

### 15.15 Hello-World debug mode

`configure(showHelloWorld: true)` always pushes a placeholder overlay. Useful as a "is the overlay layer wired?" smoke test; never ship this on.

### 15.16 Overlay ID equality

Overlays are deduplicated by `event.id`. Two overlay events with the **same** id will not re-fire `shouldShowOverlay` — the second is treated as a redundant update. If you need a refresh, vary the id.

### 15.17 Concurrent override application

`setDataToPanel(_:)` is serial inside the actor. `setDataToPanels(_:)` applies entries **in order** and returns one `Result` per entry, in the same order. If one fails, the rest still attempt — there is no short-circuit.

### 15.18 Working environment

`configure(maestroWorkingEnvironment:)` selects the Maestro-hosted backends the SDK talks to: panel/page config, the What Just Happened feed, and analytics. `.prod` uses production; `.test` and `.qa` both use Maestro's non-production hosts. You don't configure any of those URLs yourself.

It does **not** affect the multiview base URL — that one is yours, not Maestro's. To point multiview at a non-production backend, set `overrideBaseUrl` explicitly via `setMultiViewAPIConfig(overrideBaseUrl:token:)` or the structured override with `multiViewAPIConfig.overrideBaseUrl`.

### 15.19 Order of operations per event

The correct sequence after `await configure`:

1. `MaestroManager.shared.delegate = myDelegate`
2. `await userDidStartWatchingEvents(eventIDs: …)` — capture the returned interface.
3. Apply per-panel API configs (`setMultiViewAPIConfig`, `setProductAPIConfig`, `setKeyPlaysAPIConfig`, `setStatsAPIConfig`) — order between them is irrelevant.
4. Mount `MaestroPanel` in your view hierarchy.

Skipping step 3 yields an empty panel; skipping step 1 yields silent callbacks.

On layout switches within the same event session, only `setStatsAPIConfig` may need to be re-applied — and only when new listingIds appear (see §10 and §12). Re-apply **before** `updateEventData(eventIDs:)` so the new IDs are looked up against an up-to-date paths dict.

### 15.20 Stats paths are per-listing and replace wholesale

`setStatsAPIConfig(paths:)` is keyed by `listingId`, not by stat type. The SDK does **not** merge new calls into the previous map — each call **replaces** the entire `paths` dict. If you call it with only the current layout's listingIds, you lose entries for any other listings the user may revisit. Maintain a cumulative `[listingId: sportEventURI]` map on your side and pass the full map every time.

There is no `sportEventURI` field on `childListings` and the SDK does not resolve URIs on your behalf. Resolve them from your own catalog/backend before calling `setStatsAPIConfig`.

---

## 16. Troubleshooting checklist

| Symptom | Likely cause | Fix |
|---|---|---|
| No callbacks at all | Delegate deallocated (held weakly) | Retain on a long-lived owner. |
| Panel never shows | `configure` not awaited before `userDidStartWatchingEvents` | Await `configure` first. |
| Panel shows but is empty | API config not applied for this event | Call `setProductAPIConfig` / `setKeyPlaysAPIConfig` / `setStatsAPIConfig` after `userDidStartWatchingEvents`. |
| Overlay never appears | App didn't render `MaestroOverlay` from `shouldShowOverlay` | Mount `MaestroOverlay(event:)`. |
| Multiview tiles laid out wrong | Forgot to convert SDK coords | Y origin is bottom; positions are center-based. |
| Stats panel 401s repeatedly | Token expired, not refreshed | Implement `onPanelEvent` and refresh + re-apply. |
| Stats panel empty after entering multiview | New listingIds not in stats `paths` dict | Re-apply `setStatsAPIConfig` with cumulative map before `updateEventData` — see §12, §15.20. |
| Fonts wrong | `MaestroManager.shared` never accessed at launch | Touch the singleton on app start. |
| `setDataToPanel` returns `.unsupportedPanelIdentifier` | Wrong panel name | Use exactly `foxStats`, `foxKeyPlays`, `foxMultiview`. |
| Restore-from-clip returns to single stream instead of layout | Missing `snapshotCurrentMultiview()` call | Snapshot before navigating away. |
| QA env unreachable | Defaults point to prod | Pass `overrideBaseUrl` for the QA host. |

---

## Appendix: minimal end-to-end example

```swift
import SwiftUI
import MaestroKitFox

@main
struct FoxApp: App {
    @State private var host = PlayerHost()

    init() {
        Task {
            await MaestroManager.shared.configure(
                siteID: "fox-prod",
                showHelloWorld: false,
                maestroWorkingEnvironment: .prod
            )
        }
    }

    var body: some Scene {
        WindowGroup { PlayerScreen(host: host) }
    }
}

@MainActor
@Observable
final class PlayerHost {
    var maestroInterface: (any MaestroEventInterface)?
    var isPanelVisible = false
    var currentOverlay: MaestroOverlayEvent?
    let delegate = FoxMaestroDelegate()

    func startEvent(_ id: String, token: String) async {
        delegate.host = self
        MaestroManager.shared.delegate = delegate

        let iface = await MaestroManager.shared.userDidStartWatchingEvents(eventIDs: [id])
        maestroInterface = iface

        await MaestroManager.shared.setMultiViewAPIConfig(token: token)
        await MaestroManager.shared.setProductAPIConfig(
            url: "https://api.fox.com/multiview/products/\(id)",
            headers: ["Authorization": "Bearer \(token)"]
        )
        MaestroManager.shared.setKeyPlaysAPIConfig(
            url: "https://api.fox.com/keyplays/\(id)",
            headers: ["Authorization": "Bearer \(token)"]
        )
        MaestroManager.shared.setStatsAPIConfig(
            baseUrl: "https://stats.fox.com",
            paths: ["matchTimeline": "/v1/match/{eventId}/timeline"],
            headers: ["Authorization": "Bearer \(token)"]
        )
    }

    func stopEvent(_ id: String) async {
        await MaestroManager.shared.userDidStopWatchingEvents([id])
        maestroInterface = nil
    }
}

struct PlayerScreen: View {
    let host: PlayerHost

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                VideoPlayerLayer()
                    .task { await host.startEvent("evt-123", token: "…") }
                if host.isPanelVisible {
                    MaestroPanel(width: 453)
                }
            }
            if let overlay = host.currentOverlay {
                MaestroOverlay(event: overlay)
                    .padding()
            }
        }
    }
}
```

---

**Owner:** Maestro iOS team
**Questions:** ping #maestro-ios or file an issue on the SDK repo.
