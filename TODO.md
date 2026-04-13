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

## Map: GeoTrain removal (main) / preservation (branch)

The GeoTrain feature polls `fgc.opendatasoft.com` every 10s but the underlying data updates every ~30–60s (OpenDataSoft catalog, not a real-time stream). The cubic interpolation makes movement look smooth but positions are stale. Not worth the polling overhead or the misleading UX.

- [ ] **Branch off current `main` into `feature/geotrain`** before removing, so the implementation is preserved if the data source ever improves.
- [ ] **Remove from `main`**: delete `GeoTrainService.swift`, `GeoTrainServiceProviding` protocol, `GeoTrainUnit` model, `GeoTrainMarker` view, overlay toggle button, and all interpolation state from `iOS/FGCMapView.swift`. Update `PingStore`, `SharedContainer`, and `ServiceProtocols` to drop the geo train wiring.

## Map: TMB bus stops

Add TMB bus stop annotations to the existing `FGCMapView` with a zoom-level gate so performance stays solid (TMB has ~2,900 stops across Barcelona — rendering all at once as SwiftUI annotations would lag badly).

- [ ] **GTFS static integration** — add `TMBStaticService` reusing the existing GTFS ZIP parsing logic, pointed at `https://api.tmb.cat/v1/static/datasets/gtfs.zip`. Requires TMB `app_id` + `app_key` stored in settings.
- [ ] **Zoom-level gate** — only render TMB stop annotations when the map is zoomed past street level (roughly `MKCoordinateSpan` latitude delta < ~0.02). FGC stations always visible. Use `onMapCameraChange` to reactively show/hide the TMB layer.
- [ ] **Tap to show departures** — tapping a TMB stop calls `GET /v1/ibus/stops/{stop_id}` and shows upcoming buses in the existing `MapStatusPanel` bottom sheet. No live vehicle positions (TMB doesn't expose them).
- [ ] **Map toggle** — overlay control (alongside the existing GeoTrain button, or replacing it) to switch between FGC only / TMB only / both.
- [ ] **TMB `RealtimeService`** — implement `RealtimeServiceProviding` using the iBus REST API instead of GTFS-RT protobuf. Delay = iBus arrival timestamp − static scheduled time.
