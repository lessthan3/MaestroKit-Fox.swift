# Implementing Overlays — MaestroKitFox (Swift / iOS & tvOS)

This guide covers how a Fox client app surfaces **Maestro overlays**: the short-lived
animated cards the SDK draws over your video player (for example, the "Multiview is
available" announcement). It expands on [§ 8 of the Integration Guide](INTEGRATION.md#8-rendering-overlays)
with the full delegate contract, render step, lifecycle, and edge cases.

> **TL;DR** — The SDK decides *when* an overlay should appear and hands you an event;
> **your app decides where to draw it.** Store the event from `shouldShowOverlay`, then
> mount a `MaestroOverlay(event:)` view somewhere in your hierarchy. If you skip the
> render step, the overlay pipeline silently terminates and nothing appears on screen.

---

## Table of Contents

1. [What an overlay is](#1-what-an-overlay-is)
2. [The overlay pipeline](#2-the-overlay-pipeline)
3. [Step 1 — Handle the delegate callbacks](#3-step-1--handle-the-delegate-callbacks)
4. [Step 2 — Render `MaestroOverlay`](#4-step-2--render-maestrooverlay)
5. [`MaestroOverlay` parameters](#5-maestrooverlay-parameters)
6. [`MaestroOverlayEvent` public surface](#6-maestrooverlayevent-public-surface)
7. [Overlay lifecycle](#7-overlay-lifecycle)
8. [Handling taps / clicks](#8-handling-taps--clicks)
9. [Placement and sizing](#9-placement-and-sizing)
10. [tvOS focus](#10-tvos-focus)
11. [QA & debug helpers](#11-qa--debug-helpers)
12. [Edge cases & gotchas](#12-edge-cases--gotchas)
13. [Troubleshooting](#13-troubleshooting)
14. [Minimal end-to-end example](#14-minimal-end-to-end-example)

---

## 1. What an overlay is

A Maestro overlay is a small, self-contained animated card the SDK asks you to display
on top of your player — typically to announce that a feature (such as Multiview) is now
available for the current event. It auto-dismisses when its animation finishes (or after a
timeout you set) and can be tapped to trigger an action you define.

It is **not** the Maestro panel (the slide-in side rail), not a toast inside the panel,
and not the "What Just Happened" pill. Those are separate surfaces with their own views
(`MaestroPanel`, `MaestroWhatJustHappenedModule`).

---

## 2. The overlay pipeline

```
KMP decides to show an overlay
        │
        ▼
MaestroManager  ──►  your MaestroEventDelegate.shouldShowOverlay(event:) async
        │                         │
        │                         ▼
        │              you store the event in app state
        │                         │
        │                         ▼
        │              your view tree renders MaestroOverlay(event:)   ◄── REQUIRED
        │
        ▼
overlay auto-dismisses (animation end / timeout) or user taps it
        │
        ▼
MaestroManager  ──►  your MaestroEventDelegate.shouldHideOverlay() async
                                  │
                                  ▼
                       you clear the event from app state
```

The SDK owns the *decision* and the *animation*; your app owns *where it lives in the
view hierarchy* and *what a tap does*.

---

## 3. Step 1 — Handle the delegate callbacks

Two methods on your `MaestroEventDelegate` drive overlays. Both are `async` and run on
the main actor:

```swift
func shouldShowOverlay(event: MaestroOverlayEvent) async {
    host.currentOverlay = event       // store it; the view layer reads this
}

func shouldHideOverlay() async {
    host.currentOverlay = nil          // clear it so the view disappears
}
```

These are the only overlay-specific delegate methods. Everything else (rendering, the
dismiss timer, the tap target) is handled by the `MaestroOverlay` view you mount in
step 2.

> **Retain your delegate.** `MaestroManager` holds the delegate **weakly**. Keep a strong
> reference on a long-lived owner (your app coordinator or view model), or these callbacks
> never fire. See [Integration Guide § 15.1](INTEGRATION.md#151-the-delegate-is-held-weakly).

---

## 4. Step 2 — Render `MaestroOverlay`

This is the step that's easy to miss. Storing the event in `shouldShowOverlay` does
nothing visible on its own — you must mount the `MaestroOverlay` view and feed it the
stored event:

```swift
import MaestroKitFox

struct PlayerScreen: View {
    @State private var host = PlayerHost()   // holds `currentOverlay`

    var body: some View {
        VideoPlayerLayer()
            // Draw SDK-pushed overlays anchored to a corner of the player.
            .overlay(alignment: .bottomTrailing) {
                if let event = host.currentOverlay {
                    MaestroOverlay(event: event)
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                }
            }
    }
}
```

`MaestroOverlay` resolves and plays the correct animation for the event, runs the
auto-dismiss timer, and reports the lifecycle back into the SDK for you. You only supply
the event and decide where it sits.

---

## 5. `MaestroOverlay` parameters

```swift
MaestroOverlay(
    event: event,                     // required
    dismissTimeoutSeconds: nil,       // optional — omit to auto-size to the Rive animation
    onOverlayClicked: { /* … */ },
    onOverlayFinished: { /* … */ }
)
```

| Parameter | Default | Purpose |
|---|---|---|
| `event` | — | The `MaestroOverlayEvent` delivered to `shouldShowOverlay(event:)`. |
| `dismissTimeoutSeconds` | `nil` | How long the overlay stays up before auto-dismissing. When `nil` (the default), the overlay auto-sizes to the Rive animation — it dismisses when the animation finishes / the state machine settles, or after the animation's own play-through duration, whichever comes first. Pass a value only to force a fixed duration. |
| `onOverlayClicked` | `nil` | Called when the user taps / selects the overlay. Put navigation, deep-linking, and analytics here. |
| `onOverlayFinished` | `nil` | Called after the overlay finishes — by timeout, by the animation finishing, **or** by a tap. Use it to clean up any local state you keep alongside `currentOverlay`. |
| `maestroManager` | `.shared` | Leave as the default; override only for isolated testing. |

You do **not** need to clear `currentOverlay` from inside `onOverlayFinished` — the SDK
calls `shouldHideOverlay()` on your delegate as part of teardown, which is where you clear
it. `onOverlayFinished` is for *additional* host-side cleanup if you have any.

---

## 6. `MaestroOverlayEvent` public surface

The event is intentionally **opaque**. Only two members are public:

| Member | Type | Notes |
|---|---|---|
| `id` | `String` | Stable identifier. Overlays are de-duplicated by this — see § 12. |
| `size` | `CGSize` | Suggested render size in points. |

You never construct a `MaestroOverlayEvent` yourself — you only receive one from
`shouldShowOverlay(event:)` and pass it straight back into `MaestroOverlay(event:)`.
Don't try to read animation contents, target panels, or CTA data off it; that's internal
and handled by the view.

---

## 7. Overlay lifecycle

1. The overlay fades in on appear (~0.35s).
2. It stays up until the first of these happens:
   - the user taps it;
   - **if `dismissTimeoutSeconds` was set** — that timeout elapses;
   - **otherwise (default)** — the Rive animation finishes / the state machine settles, or
     the animation's measured play-through duration elapses. A 12s safety net covers looping
     content that never settles and files that expose no readable duration.
3. On tap: `onOverlayClicked` runs, then the overlay begins dismissing.
4. On dismiss (any path): the overlay fades out, `onOverlayFinished` runs, and the SDK
   calls `shouldHideOverlay()` on your delegate so you can clear `currentOverlay`.

A given overlay finishes **exactly once** — whichever signal fires first wins and the rest
are ignored, so the paths never double-fire for the same event.

---

## 8. Handling taps / clicks

When the user activates the overlay, your `onOverlayClicked` closure is invoked. This is
where the host performs whatever the overlay is advertising — most commonly, opening a
Maestro panel:

```swift
MaestroOverlay(
    event: event,
    onOverlayClicked: {
        // Example: route the user into the Multiview panel. `interface` is the
        // MaestroEventInterface you captured from `userDidStartWatchingEvents`.
        host.maestroInterface?.didShowPanel(panelTypeId: .multiview)
        analytics.track("maestro_overlay_tapped")
    }
)
```

> **Navigation is the host's job.** The overlay view does not auto-route to a panel on
> tap — it surfaces the tap to you via `onOverlayClicked`, and you decide what happens.
> `didShowPanel(panelTypeId:)` on the `MaestroEventInterface` both selects the requested
> tab in the SDK and triggers `shouldShowPanel()` on your delegate so you can present the
> panel — see [Integration Guide § 7](INTEGRATION.md#7-presenting-the-maestro-panel).

---

## 9. Placement and sizing

- Anchor the overlay to a corner of the player with `.overlay(alignment:)` and add
  padding so it clears safe areas and player chrome. The reference integration uses
  `.bottomTrailing` with 20pt insets.
- `MaestroOverlay` sizes itself from the event and its animation; you don't need to set an
  explicit frame. `event.size` is available if you want to reserve layout space.
- Keep the overlay above your player layer but below any modal/sheet UI so it doesn't
  fight focus or touch handling with full-screen presentations.

---

## 10. tvOS focus

On tvOS, `MaestroOverlay` makes itself focusable and **auto-focuses shortly after it
appears** so the Siri remote select button triggers `onOverlayClicked`. Make sure a
sibling view isn't trapping focus, or the user won't be able to move to/from the overlay.
Wrap the rest of your screen in its own focus section if needed.

---

## 11. QA & debug helpers

### Smoke-test the render path (`showHelloWorld`)

Passing `showHelloWorld: true` to `configure` makes the SDK push a placeholder overlay.
It's a quick "is my overlay layer wired up?" check — if nothing appears with this on, your
render step (§ 4) is missing or your delegate isn't retained. **Never ship with it on.**

```swift
await MaestroManager.shared.configure(
    siteID: "fox-prod",
    showHelloWorld: true,            // QA only
    maestroWorkingEnvironment: .qa
)
```

### Re-trigger the one-time Multiview overlay

The Multiview availability overlay is shown **once per install** — the "already shown"
gate lives in the SDK. To re-test it without reinstalling, reset the gate:

```swift
await MaestroManager.shared.resetMultiviewOverlay()
```

---

## 12. Edge cases & gotchas

### 12.1 The render step is mandatory
Storing the event in `shouldShowOverlay` is not enough. If your view tree never mounts
`MaestroOverlay(event:)`, the SDK pushes events and **nothing draws** — the pipeline looks
dead from the outside. This is the single most common overlay integration bug.

### 12.2 Overlays are de-duplicated by `id`
Two overlay events with the **same** `id` will not re-fire `shouldShowOverlay` — the second
is treated as a redundant update and dropped. If you need to force a refresh during testing,
the id has to change.

### 12.3 The dismiss timing is driven Swift-side
By default (`dismissTimeoutSeconds: nil`) the overlay stays up for the Rive animation's own
length — it dismisses when the animation finishes / the state machine settles, or after the
animation's measured play-through duration, backstopped by a 12s fallback. A state machine
has no single duration, so the duration is read from the linear animations on the artboard;
a looping state machine never settles and relies on the fallback. Passing an explicit
`dismissTimeoutSeconds` overrides all of this with a fixed duration. A *server-supplied*
duration on the event is **not** honored — timing comes from the animation or the value you
pass, never a back-end field.

### 12.4 Delegate methods are `async` and main-actor
Both `shouldShowOverlay` and `shouldHideOverlay` are `async @MainActor`. Update your UI
state directly inside them; don't hop threads.

### 12.5 Clearing state
Clear `currentOverlay` in `shouldHideOverlay()`, not in `onOverlayFinished`. The SDK drives
`shouldHideOverlay` as the canonical teardown signal; `onOverlayFinished` is supplementary.

### 12.6 Re-starting an event finalizes the current overlay
If you call `userDidStartWatchingEvents` again while an overlay is up, the SDK finalizes it
first — your `shouldHideOverlay` fires one last time. See
[Integration Guide § 15.3](INTEGRATION.md#153-re-starting-an-event-without-stopping-the-previous-one).

---

## 13. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Overlay never appears | Render step missing | Mount `MaestroOverlay(event:)` from your stored `currentOverlay` (§ 4). |
| `shouldShowOverlay` never called | Delegate deallocated (held weakly) | Retain the delegate on a long-lived owner. |
| Overlay appears but tap does nothing | `onOverlayClicked` not provided, or focus trapped (tvOS) | Pass `onOverlayClicked`; ensure no sibling traps focus. |
| Overlay won't re-trigger in QA | Same `id` (deduped) or one-time gate already set | Vary the id, or call `resetMultiviewOverlay()`. |
| Overlay dismisses too fast/slow | Default follows the Rive animation length | Pass an explicit `dismissTimeoutSeconds` to force a fixed duration — server value isn't honored (§ 12.3). |
| Placeholder overlay keeps showing | `showHelloWorld: true` left on | Set it to `false` for non-QA builds. |

---

## 14. Minimal end-to-end example

```swift
import SwiftUI
import MaestroKitFox

@MainActor
@Observable
final class PlayerHost {
    var currentOverlay: MaestroOverlayEvent?
    var maestroInterface: (any MaestroEventInterface)?
    let delegate = FoxMaestroDelegate()

    func start() async {
        delegate.host = self
        MaestroManager.shared.delegate = delegate    // retained via `delegate` property
        maestroInterface = await MaestroManager.shared.userDidStartWatchingEvents(eventIDs: ["evt-123"])
    }
}

@MainActor
final class FoxMaestroDelegate: MaestroEventDelegate {
    typealias MaestroOverlayEvent = MaestroKitFox.MaestroOverlayEvent
    weak var host: PlayerHost?

    func shouldShowOverlay(event: MaestroOverlayEvent) async {
        host?.currentOverlay = event
    }

    func shouldHideOverlay() async {
        host?.currentOverlay = nil
    }

    // … remaining MaestroEventDelegate methods (see Integration Guide § 4) …
}

struct PlayerScreen: View {
    @State private var host = PlayerHost()

    var body: some View {
        VideoPlayerLayer()
            .overlay(alignment: .bottomTrailing) {
                if let event = host.currentOverlay {
                    MaestroOverlay(
                        event: event,
                        // dismissTimeoutSeconds omitted — auto-sizes to the Rive animation
                        onOverlayClicked: {
                            host.maestroInterface?.didShowPanel(panelTypeId: .multiview)
                        }
                    )
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
            .task { await host.start() }
    }
}
```

---

**See also:** [INTEGRATION.md](INTEGRATION.md) (full integration guide) ·
[LOGGING.md](LOGGING.md) (SDK console logging for overlay lifecycle debugging).

**Owner:** Maestro iOS team · **Questions:** ping #maestro-ios or file an issue on the SDK repo.
</content>
</invoke>
