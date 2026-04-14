# Ping TODO

## Status

- [ ] Tracking UX parity (App + Live Activity): split behavior into `Planning` vs `TrackingLocked`.
- [ ] Before Follow Trip (`Planning`): app hero can auto-roll to next catchable train.
- [ ] After Follow Trip (`TrackingLocked`): lock to selected train `tripID` in both app hero and Live Activity.
- [ ] In `TrackingLocked`, show tracking-focused state (`ETA to station`, `train departs in`, `buffer +/-`) instead of planner-only countdown behavior.
- [ ] If tracked train is likely missed/missed: show explicit status and action (`Switch to next train`) instead of silent auto-switching.

## Visual Polish (Metal Shaders)

Uses SwiftUI's `.colorEffect()` / `.distortionEffect()` modifiers (iOS 17+, no UIKit needed). Shader `.metal` files go in a new `Shaders/` directory added to the iOS target. Time uniforms can be fed from the existing `TimelineView` that drives the countdown.

- [ ] **Shimmer sweep on hero card** — diagonal light glint sweeps left-to-right on `TrainHeroCard` (~3s loop) when tracking a live train. Signals "live data" without extra UI. `iOS/ContentView.swift` → `TrainHeroCard`, driver: `TimelineView` time uniform → `ShaderLibrary.shimmer(.float(time))`.
- [ ] **Flowing wave in timeline bars** — subtle sine-wave brightness ripple moving through the walk (blue) and ride (green) `RoundedRectangle` bars, conveying motion/transit. `iOS/ContentView.swift` → timeline bar `HStack` in `TrainHeroCard` → `ShaderLibrary.progressWave(.float(time))`.
- [ ] **Animated glow border on hero card** — soft blue→green gradient border that breathes (pulses) when tracking; amplitude/speed increase when departure < 5 min to signal urgency. `iOS/ContentView.swift` → `TrainHeroCard` overlay stroke → `ShaderLibrary.glowBorder(.float(phase), .float4(color))`.
- [ ] **Noise texture on card backgrounds** — near-invisible grain (±3% luminance) over `TrainHeroCard` and `NoticeCard` backgrounds for tactile depth on OLED. One shader, many callsites. `iOS/ContentView.swift` → `ShaderLibrary.noiseOverlay(.float(0.03))`.
- [ ] **Radial pulse on origin station marker** — expanding ring fades out from origin `StationMarker` on the map (~2s repeat, SwiftUI scale+opacity animation, no shader strictly required but can be done with a `.colorEffect` falloff shader). `iOS/FGCMapView.swift` → `StationMarker`.

## Map: TMB bus stops

Completed baseline integration (GTFS static load, zoom-gated rendering, and tap-to-load arrivals). Remaining follow-ups:

- [ ] **Map toggle modes** — extend overlay control from current on/off to explicit `FGC only` / `TMB only` / `both`.
- [ ] **TMB delay model** — enrich realtime layer so delay is computed as `iBus arrival timestamp − static scheduled time`.

## Haptic Feedback

Uses SwiftUI's `.sensoryFeedback` modifier (iOS 17+) — no UIKit needed. All feedback is contextual and tied to meaningful moments, not decorative.

- [ ] **"Leave now" impact** — heavy impact when the TrackingLocked countdown crosses the leave threshold (i.e. the "leave now" notification fires). `iOS/NotificationScheduler.swift` + `iOS/ContentView.swift`.
- [ ] **< 2 min warning** — warning notification feedback (double tap pattern) when `minutesUntilDeparture` drops to 2 while in `TrackingLocked`. `iOS/ContentView.swift` → `HeroCountdownValue` or `TrainHeroCard` via `onChange`.
- [ ] **Missed train** — error feedback when the tracked train transitions to missed status. `iOS/ContentView.swift` → `TrackingLocked` state handler.
- [ ] **Route confirmed** — light success feedback when user taps "Follow trip" to enter `TrackingLocked`. `iOS/ContentView.swift`.

## Actionable Notifications

Extend the existing `NotificationScheduler` with `UNNotificationAction` categories so users can act on alerts without opening the app.

- [ ] **"Switch to next train" action** — add a `UNNotificationAction` to the missed-train notification (ties into the `TrackingLocked` missed-train TODO). Tapping it triggers the switch via a background notification handler without foregrounding the app. `iOS/NotificationScheduler.swift` + `iOS/AppDelegate` / scene delegate notification handler.
- [ ] **"Snooze 5 min" action** — on the "leave now" reminder, allow a 5-minute snooze that reschedules the notification. `iOS/NotificationScheduler.swift`.

## Siri & App Intents

Uses the App Intents framework (iOS 16+). No SiriKit legacy code needed. Intents live in a new `iOS/Intents/` group.

- [ ] **`NextDepartureIntent`** — zero-parameter intent using the saved home→work route from settings. Siri response: *"Next train departs in 8 minutes at 9:42, arriving at Sarrià at 9:56."* Donate on every app launch so Siri proactively suggests it on the lock screen after learning the morning pattern. `iOS/Intents/NextDepartureIntent.swift`.
- [ ] **`DeparturesBetweenStopsIntent`** — two-parameter intent with `origin: StopEntity` and `destination: StopEntity`. Resolves stop names against the GTFS static dataset. Handles disambiguation when multiple stops match a query (e.g. "Gràcia" matches several). Siri prompts for missing parameters automatically. `iOS/Intents/DeparturesBetweenStopsIntent.swift`.
- [ ] **`StopEntity`** — `AppEntity` wrapping `Stop`, with `StringSearchableEntityQuery` backed by `FGCStaticService.searchStops()`. Required for Siri to resolve spoken stop names. `iOS/Intents/StopEntity.swift`.
- [ ] **`PingShortcutsProvider`** — `AppShortcutsProvider` that surfaces both intents in the Shortcuts app with suggested phrases (e.g. *"Next train in Ping"*, *"Departures from [origin] to [destination] in Ping"*). `iOS/Intents/PingShortcutsProvider.swift`.
- [ ] **Intent donation** — call `NextDepartureIntent.donate()` each time the user searches a route, so Siri learns the most-used pairs and proactively suggests them.
