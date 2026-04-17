# Ping

macOS menu bar + iOS app for tracking FGC (Ferrocarrils de la Generalitat de Catalunya)
train departures in the Barcelona area, with a secondary TMB (metro/bus) layer. Powered
by GTFS static + realtime.

Core features: unified origin/destination picker, saved routes + favorite stations,
time-of-day suggestions, commute tracking with leave-now notifications, service alerts,
calendar-aware suggestions, widgets, and a Live Activity.

## Build

- Swift 6.3, macOS 15+, iOS 18+
- `swift build` — shared library
- `swift test` — run tests
- `xcodegen` regenerates `Ping.xcodeproj` from `project.yml`

## Architecture

- `Shared/` — `PingShared` Swift package: models, services (FGC/TMB static + realtime,
  calendar, service alerts, location, walking ETA, GTFS updates, notifications), engine
  (`CommuteEngine`, `PingStore`), cross-platform SwiftUI views
- `iOS/` — iOS app (home planner, map, settings, commute tracker UI)
- `macOS/` — macOS menu bar app (`MenuBarView`)
- `Widgets/` — WidgetKit + Live Activity
- `Tests/PingSharedTests/` — tests for the shared library

## Dependencies

- [swift-protobuf](https://github.com/apple/swift-protobuf) — GTFS realtime protobuf parsing
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) — GTFS static ZIP extraction
