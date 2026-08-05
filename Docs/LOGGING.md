# MaestroKitFox — Console logging

The SDK can print its lifecycle events (panel selection, overlay flow, presenter start/stop, KMP state transitions) to the Xcode console for debugging. Off by default; flip a single toggle to turn it on.

```swift
import MaestroKitFox

// Turn on for debug builds, leave off in release.
Task {
    #if DEBUG
    await MaestroManager.shared.setConsoleLoggingEnabled(true)
    #endif
}
```

Every line is prefixed with `[Maestro]` so you can filter the Xcode console.

```
[Maestro] panelSelectionRequested(panel: "foxKeyPlays", source: MaestroKitFox.MaestroLogEvent.PanelSelectionSource.hostRequest)
[Maestro] selectedPanelChanged(panel: Optional("foxKeyPlays"))
[Maestro] enabledPanelsChanged(panels: ["foxMultiView", "foxKeyPlays", "foxStats"])
[Maestro] panelSelected(tab: "keyPlays", panel: Optional("foxKeyPlays"))
```

Turn it off again with `setConsoleLoggingEnabled(false)`. The toggle is process-global; the SDK writes nothing to the console when it's off.

## What gets logged

The SDK emits events for:

- **Panel selection** — host requests, KMP state changes, resolved tab, and fallbacks when the requested panel can't be honored.
- **Overlay lifecycle** — received from KMP, shown, clicked, dismissed (with reason), finished.
- **Presenters** — start/stop for the multiview / keyPlays / stats / overlay presenters.
- **Feature flags** — the resolved flag map applied to each panel.

If you're investigating "the CTA opened the wrong panel," look for a `panelSelectionRequested` followed by a `panelSelectionFallback` — that pair is the signal the requested panel couldn't be honored at mount time.
