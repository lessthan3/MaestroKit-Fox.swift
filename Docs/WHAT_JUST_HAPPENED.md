# What Just Happened — Fox Integration Notes (Swift / iOS & tvOS)

These notes describe how the Fox client app integrates the **What Just Happened (WJH)** feature on top of **MaestroKitFox**. WJH surfaces AI-generated recaps of significant moments during a live event. It rides on the standard SDK lifecycle described in [`INTEGRATION.md`](./INTEGRATION.md) — read that first; this document only covers what is WJH-specific.

TL;DR — once the base SDK is wired up (configure, delegate, start event, present `MaestroPanel`), WJH is two additions:

1. Embed `MaestroWhatJustHappenedModule()` next to your player to get the floating recap pill.
2. The **WJH panel tab** appears automatically inside `MaestroPanel`.

The SDK renders all WJH UI and manages the data itself. The host app builds no WJH UI, parses no JSON, and manages no polling — it presents the SDK's views and handles the one panel callback it already implements.

---

## Table of Contents

1. [What WJH is](#1-what-wjh-is)
2. [The two surfaces](#2-the-two-surfaces)
3. [Surface A — the floating module](#3-surface-a--the-floating-module)
4. [Surface B — the WJH panel tab](#4-surface-b--the-wjh-panel-tab)
5. [The "Explore More" round-trip](#5-the-explore-more-round-trip)
6. [Configuration](#6-configuration)
7. [Reference: public types](#7-reference-public-types)
8. [Minimal end-to-end example](#8-minimal-end-to-end-example)
9. [Edge cases & gotchas](#9-edge-cases--gotchas)
10. [Verification checklist](#10-verification-checklist)

---

## 1. What WJH is

WJH drives **two complementary surfaces** from the same recap data:

- **Module** — a floating **pill** that appears when a noteworthy moment lands, expands on press into a short recap with **Dismiss** / **Explore More**, and auto-hides.
- **Panel** — a tab in the Maestro panel that shows the full recap: an optional **summary** plus a **timeline** of moments.

Both surfaces are rendered by the SDK: the pill for ambient discovery during play, the panel tab for browsing the full timeline.

---

## 2. The two surfaces

| Surface | Host integration | Auto-shown? |
|---|---|---|
| **Floating module** | Add `MaestroWhatJustHappenedModule()` to your view tree | Yes — draws nothing until a moment surfaces |
| **Panel tab** | None beyond presenting `MaestroPanel` | Yes — appears as a tab when the event's panel config includes WJH |

---

## 3. Surface A — the floating module

Embed `MaestroWhatJustHappenedModule()` alongside your player content. It is a self-contained SwiftUI view that **draws nothing while hidden**, so it is safe to leave mounted for the whole session.

```swift
VideoPlayerLayer()
    .overlay(alignment: .bottomLeading) {
        MaestroWhatJustHappenedModule()      // floats over the player; hidden until a moment lands
            .padding()
    }
```

`MaestroWhatJustHappenedModule` has a parameterless initializer and manages its own observation lifecycle — just mount it and leave it.

### What the user sees

The module moves through three phases, all driven by the SDK:

| Phase | What the user sees | Transition |
|---|---|---|
| **Hidden** | Nothing | A noteworthy moment surfaces → **Pill** |
| **Pill** | Compact label ("What Just Happened?") with animated border | Auto-hides after the visibility window (~10s) back to **Hidden**; user presses it to go to **Expanded** |
| **Expanded** | Recap text + **Dismiss** / **Explore More** | Dismiss / auto-expire returns to **Hidden**; Explore More opens the WJH panel, then **Hidden** |

You do not drive any of these transitions yourself — the SDK view handles the gestures and focus.

### tvOS focus

The module is focusable on tvOS. Keep it in its own focus section and make sure it isn't trapped behind a sibling that captures focus, or the pill won't be reachable. See [`INTEGRATION.md` §15.7](./INTEGRATION.md#157-tvos-focus).

---

## 4. Surface B — the WJH panel tab

The **What Just Happened** tab renders:

- a **summary** card (when present), and
- a scrollable **timeline** of recap cards (sticky-header list on tvOS, plain scroll on iOS).

There is **nothing to wire**. As long as you present `MaestroPanel` as in [`INTEGRATION.md` §7](./INTEGRATION.md#7-presenting-the-maestro-panel), the tab shows up whenever the event's panel configuration includes WJH. Visibility is driven by the server-side panel config for the site/event.

```swift
// Standard panel presentation — the WJH tab rides along inside it.
if host.isPanelVisible {
    MaestroPanel(width: 453)   // pass nil for flex width on iOS
        .transition(.move(edge: .trailing))
}
```

The same show/hide contract applies: present the panel on `shouldShowPanel()`, then confirm with `interface.didShowPanel()`.

---

## 5. The "Explore More" round-trip

When the user presses **Explore More** on the expanded module, the SDK reveals the panel and switches it to the WJH tab. From the host's side this happens through the panel callback you already implement:

1. The SDK calls your `MaestroEventDelegate.shouldShowPanel()` — **you must present `MaestroPanel`** (the same callback you handle for every panel).
2. The SDK selects the WJH tab inside the panel.

**Action required:** none beyond correctly handling `shouldShowPanel()` / `shouldHidePanel()`. If "Explore More" appears to do nothing, your `shouldShowPanel()` handler isn't actually presenting the panel — that's the bug, not WJH.

---

## 6. Configuration

In the integrated path **the host configures nothing WJH-specific.** Site and environment come from your existing `configure(siteID:maestroWorkingEnvironment:)` call, and the per-event recap feed and surfacing behavior are configured server-side. The SDK wires everything up automatically when the event starts.

### Why the pill sometimes doesn't appear

The **module** pill only surfaces moments the server has flagged as noteworthy enough, so it may stay hidden while the **panel** timeline already has content. An empty pill with a populated panel tab is expected behavior, not a defect.

---

## 7. Reference: public types

Host-facing entry points:

| Symbol | Purpose |
|---|---|
| `MaestroWhatJustHappenedModule()` | SwiftUI view — the floating pill/expanded module |
| `MaestroPanel(width:)` | Hosts the WJH tab (and all other Fox panels) |
| `MaestroEventDelegate.shouldShowPanel()` | Must present the panel; powers "Explore More" |

---

## 8. Minimal end-to-end example

This is the base-SDK example from [`INTEGRATION.md`](./INTEGRATION.md#appendix-minimal-end-to-end-example) with the two WJH additions.

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
                maestroWorkingEnvironment: .prod
            )
        }
    }

    var body: some Scene {
        WindowGroup { PlayerScreen(host: host) }
    }
}

struct PlayerScreen: View {
    let host: PlayerHost

    var body: some View {
        HStack(spacing: 0) {
            VideoPlayerLayer()
                .task { await host.startEvent("evt-123", token: "…") }

            if host.isPanelVisible {
                MaestroPanel(width: 453)              // WJH tab lives here, no extra wiring
            }
        }
        .overlay(alignment: .bottomLeading) {
            MaestroWhatJustHappenedModule()           // floating recap pill, hidden until a moment lands
                .padding()
        }
    }
}
```

`PlayerHost` and the delegate are exactly as in the base guide. The only delegate requirement WJH adds is that `shouldShowPanel()` actually presents `MaestroPanel` — which you already implement.

---

## 9. Edge cases & gotchas

- **Pill never appears, panel tab has content.** Expected when no moment has been flagged noteworthy enough to surface yet — see §6.
- **"Explore More" does nothing.** Your `shouldShowPanel()` isn't presenting the panel. Fix the panel show/hide contract.
- **Module is mounted but invisible.** That's correct in the Hidden phase — it draws nothing. Don't conditionally remove it; leave it mounted so it can appear when a moment surfaces.
- **tvOS pill unreachable.** A sibling is trapping focus. Give the module its own focus section.
- **Stale recaps after switching events.** WJH is tied to the active event. Call `userDidStopWatchingEvents([…])` before starting the next event so WJH is rebuilt for it.
- **Don't mount the module twice.** `MaestroWhatJustHappenedModule` manages its own observation; mounting it more than once creates duplicate observers.

---

## 10. Verification checklist

- [ ] `import MaestroKitFox` builds on both the iOS and tvOS targets (deployment ≥ 18.0).
- [ ] Base SDK lifecycle works: configure, delegate set, `userDidStartWatchingEvents`, `MaestroPanel` shows on `shouldShowPanel()` and is confirmed with `didShowPanel()`.
- [ ] `MaestroWhatJustHappenedModule()` is mounted near the player and draws nothing while idle.
- [ ] The **What Just Happened** tab appears inside `MaestroPanel` for a WJH-enabled event.
- [ ] A surfacing moment shows the pill; pressing it expands the recap.
- [ ] **Dismiss** hides the module; auto-hide fires after the visibility window.
- [ ] **Explore More** opens the panel on the WJH tab (confirms `shouldShowPanel()` is correct).
- [ ] On tvOS the pill is focusable and reachable.

---
**Owner:** Maestro Apple Team
