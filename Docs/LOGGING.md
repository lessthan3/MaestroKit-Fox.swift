# MaestroKitFox — Console logging

The SDK writes its lifecycle events (panel selection, overlay flow, presenter start/stop, KMP state transitions) to the unified logging system. There is nothing to turn on: **debug builds log everything, release builds log only errors.**

Logs go to `os_log` under the subsystem `com.maestro.sdk.swift`, category `General`. They appear in the Xcode console while you're running, and in Console.app for a build running on a device.

Every SDK lifecycle line is prefixed with `[Maestro]`, and feature-level lines with a tag like `[Overlay]`, so you can filter either in Xcode's console filter field or in Console.app.

```
[MaestroManager.swift:setInstance(_:):148] [Maestro] presenter started: overlay
[FoxPanelViewModel.swift:start():115] [Maestro] enabled panels changed: ["foxMultiView", "foxKeyPlays", "foxStats"]
[FoxPanelViewModel.swift:start():153] [Maestro] selected panel changed: foxKeyPlays
[MaestroOverlay.swift:onClicked():133] [Overlay] onClicked id=a1b2c3d4e5f6, …
```

To capture logs from a release build on a device, use Console.app with the subsystem filter — errors come through there without a debug build.

## What gets logged

- **Panel selection** — host requests, KMP state changes, the resolved tab, and fallbacks when the requested panel can't be honored.
- **Overlay lifecycle** — received from KMP, shown, clicked, dismissed (with reason), finished.
- **Presenters** — start/stop for the multiview / keyPlays / stats / overlay presenters.
- **Feature flags** — the resolved flag map applied to each panel.

If you're investigating "the CTA opened the wrong panel," find the `panel selection resolved` line. It records the requested panel id, the panel ids currently enabled, and whether a host delegate is attached — which separates *the id matched no enabled panel* from *no delegate was there to present it*.
