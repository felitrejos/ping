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
