# Analytics — Fox Integration Notes (Swift / iOS & tvOS)

These notes describe how the Fox client app receives and forwards analytics from **MaestroKitFox**. Analytics rides on the standard SDK lifecycle in [`INTEGRATION.md`](./INTEGRATION.md) — read that first; this document covers only what is analytics-specific.

TL;DR — MaestroKitFox doesn't own your analytics pipeline. It hands every action and impression to your event delegate as a ready-made `[String: String]` dictionary. Your job is one thing: **implement `trackAction` / `trackImpression` and forward the dictionary verbatim** to Fox's analytics SDK (Segment, Adobe, etc.).

---

## Table of Contents

1. [Integration point](#1-integration-point)
2. [What you'll receive](#2-what-youll-receive)
   - [2.1 Payload schema (key reference)](#21-payload-schema-key-reference)
3. [Forward the payload verbatim](#3-forward-the-payload-verbatim)
4. [Enabling & debugging](#4-enabling--debugging)
5. [Minimal end-to-end example](#5-minimal-end-to-end-example)
6. [Reference & gotchas](#6-reference--gotchas)
7. [Verification checklist](#7-verification-checklist)

---

## 1. Integration point

There is one thing to wire up: implement `trackAction` / `trackImpression` on your `MaestroEventDelegate` and forward what you receive.

| What | Direction |
|---|---|
| Implement `trackAction` / `trackImpression` on your `MaestroEventDelegate` | SDK → you |

The SDK builds the events; you decide where they go.

---

## 2. What you'll receive

The two callbacks live on your `MaestroEventDelegate` (the same delegate you already register for panel and event callbacks). They cover all Maestro surfaces — multiview, key plays, stats, What Just Happened, overlays.

```swift
func trackAction(analytics: [String: String])      // user actions (taps, selections)
func trackImpression(analytics: [String: String])  // a surface appeared (views)
```

- **`trackAction`** fires on discrete user actions — selecting a multiview layout, adding/removing a stream, clicking a key play, expanding a card, "See all" CTAs, back navigation.
- **`trackImpression`** fires when a surface becomes visible.

Both are delivered on the main actor, asynchronously, shortly after the interaction — not synchronously with the gesture. Treat the `analytics` dictionary as an **opaque, ready-to-send payload**: it already contains the event name, panel context, session, and device fields your pipeline needs.

### 2.1 Payload schema (key reference)

You don't need to read or branch on these keys — forward the dictionary verbatim (see §3). This reference is here only so you can recognize the fields when debugging a payload or mapping them in a downstream tool.

> **Two quick answers up front:**
> - **Where's the metadata?** The key is literally **`metadata`**. (Some internal specs write it as `e_m`, short for "event metadata" — the SDK does **not** emit a key named `e_m`. Read `analytics["metadata"]`.)
> - **Which panel did this event fire for?** Look at **`e2_class`** (panel type), **`e3_order`** (panel ID), and **`e4_family`** (panel name). Those three identify the surface; the `metadata` value carries the per-event details, not the panel identity.

Every event is a flat `[String: String]`. The keys use a **biological-taxonomy naming scheme** (`kingdom → phylum → class → order → family`) that classifies an event from broadest to most specific. The `e0`…`e4` prefixes preserve that ordering when keys are sorted alphabetically.

| Key | Taxonomy slot | What the value is |
|---|---|---|
| `e0_kingdom` | kingdom | Broadest event grouping (the top of the classification). |
| `e1_phylum` | phylum | Next level down within the kingdom. |
| `e2_class` | class | **Panel type** — which Maestro surface (e.g. multiview, key plays, stats). |
| `e3_order` | order | **Panel ID** — the identifier of the specific panel instance. |
| `e4_family` | family | **Panel name** — the human-readable panel name. |
| `metadata` | — | Optional. A **JSON-encoded string** holding extra per-event context (string or string-array values). Present only when the event carries metadata; omitted otherwise. |

The exact `kingdom`/`phylum` values and the contents of `metadata` are driven by Maestro's server-side configuration for the site and event, so they vary by surface and over time — treat them as data, not as a fixed enum.

> **`metadata` is a nested payload flattened into one string.** Because the contract is `[String: String]`, any structured per-event context is JSON-encoded into the single `metadata` value (with sorted keys, so it's deterministic). If your pipeline needs those inner fields broken out, `JSONSerialization.jsonObject(...)`-decode `analytics["metadata"]` downstream — don't reshape the top-level dictionary before forwarding it.

#### `metadata` examples

The shape of `metadata` depends on the kind of event. The two you'll see most are **view** events (a surface appeared, `e1_phylum = view`, delivered via `trackImpression`) and **engage/interact** events (a user acted, `e1_phylum = engage`, delivered via `trackAction`).

**View event** — viewing a panel. The metadata identifies the content context:

```json
{ "league": "league_id", "event": "event_id", "airing": "airing_id", "sport": "sport_id" }
```

Some surfaces add their own context — e.g. the Stats panel includes `game_state`:

```json
{ "league": "league_id", "event": "event_id", "airing": "airing_id", "sport": "sport_id", "game_state": "in" }
```

**Engage / interact events** — a discrete action. These carry an `event_name` naming the action, plus fields specific to it:

```json
// "See all stats" tapped in multiview
{ "event_name": "stats_expand", "entity_id": "listing_id" }

// Layout card selected (changing the multiview layout)
{ "event_name": "mv_layout_select", "entity_id": ["listing_id"], "layout_type": "layout_id", "spotlight_entity_id": "listing_id_in_spotlight" }

// Stream added to / removed from a multiview
{ "event_name": "mv_stream_add", "entity_id": ["listing_id"], "title": "title" }

// A specific key play clicked
{ "event_name": "keyplay_click", "key_play_type": "key_play_type", "key_play_id": "key_play_id", "sport_uri": "sport_event_uri", "description": "description", "entity_id": "listing_id" }

// Expanding / collapsing a card — `card` is "statsMatchTimelineCard", "statsTeamStatsCard", or "statsLeagueScoresCard"
{ "action": "expand", "card": "card" }
```

The exact field set varies by surface and evolves over time — treat any field as optional and don't hard-code on its presence.

---

## 3. Forward the payload verbatim

The dictionary keys are stable and intentional. Forward the dictionary **without transforming, renaming, or dropping keys** — map the whole thing to a single analytics call.

```swift
extension FoxMaestroDelegate {
    func trackAction(analytics: [String: String]) {
        FoxAnalytics.shared.track(name: "maestro_action", properties: analytics)
    }

    func trackImpression(analytics: [String: String]) {
        FoxAnalytics.shared.track(name: "maestro_impression", properties: analytics)
    }
}
```

If your downstream needs a friendlier event name, derive one alongside the payload rather than reshaping it.

---

## 4. Enabling & debugging

**Gating.** Analytics is enabled or disabled by Maestro's remote configuration for the site — there is no client flag for you to set. If you expect events and see none, confirm analytics is enabled for the site config and that an event is active. When disabled, your delegate simply isn't called.

**Debugging.** Enable console logging during bring-up, or log the dictionaries directly in your delegate:

```swift
await MaestroManager.shared.setConsoleLoggingEnabled(true)   // see LOGGING.md

func trackAction(analytics: [String: String]) {
    #if DEBUG
    print("[Maestro][action]", analytics)
    #endif
    FoxAnalytics.shared.track(name: "maestro_action", properties: analytics)
}
```

---

## 5. Minimal end-to-end example

The only addition over the base [`INTEGRATION.md`](./INTEGRATION.md) example is implementing the two track methods on your delegate.

```swift
import MaestroKitFox

@MainActor
final class FoxMaestroDelegate: MaestroEventDelegate {

    // --- Analytics: forward verbatim --------------------------------------
    func trackAction(analytics: [String: String]) {
        FoxAnalytics.shared.track(name: "maestro_action", properties: analytics)
    }

    func trackImpression(analytics: [String: String]) {
        FoxAnalytics.shared.track(name: "maestro_impression", properties: analytics)
    }

    // --- Other required delegate methods (panel, multiview, key plays…) ----
    func shouldShowPanel() { /* present MaestroPanel */ }
    func shouldHidePanel() { /* dismiss MaestroPanel */ }
    func onKeyPlaySelected(event: KeyPlayClipInfo) {}
    func onNewMultiview(event: NewMultiviewEvent) {}
    func onKeyPlayListChanged(keyPlays: [KeyPlayClipInfo]) {}
    func onNewSingleStream(event: NewSingleStreamEvent) {}
    func onPanelEvent(event: PanelEvent) {}
    // …plus the base MaestroEventDelegate overlay methods.
}
```

Register it as usual (`MaestroManager.shared.delegate = …` before starting the event).

---

## 6. Reference & gotchas

| Symbol | Purpose |
|---|---|
| `MaestroEventDelegate.trackAction(analytics:)` | Receives user-action events; forward verbatim |
| `MaestroEventDelegate.trackImpression(analytics:)` | Receives impression/view events; forward verbatim |

- **Don't transform the dictionary.** Treat it as opaque and forward the original to one analytics call.
- **Callbacks are async** and arrive on the main actor shortly after the interaction — don't tie UI transitions to them.
- **The delegate is held weakly** by the SDK — retain it yourself, or analytics callbacks stop. See [`INTEGRATION.md` §15.1](./INTEGRATION.md#151-the-delegate-is-held-weakly).
- **No events arriving?** Confirm analytics is enabled in the site config and that `userDidStartWatchingEvents` returned an active interface.

---

## 7. Verification checklist

- [ ] `trackAction` and `trackImpression` are implemented on your `MaestroEventDelegate` and forward the dictionary verbatim.
- [ ] The delegate is registered before the event starts and is strongly retained.
- [ ] Interacting with a panel (e.g. selecting a multiview layout) triggers `trackAction`; opening a surface triggers `trackImpression`.
- [ ] With analytics disabled in the site config, no events arrive.

---
**Owner:** Maestro Apple Team
