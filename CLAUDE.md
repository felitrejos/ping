# Ping

A macOS menu bar + iOS app for tracking FGC (Ferrocarrils de la Generalitat de Catalunya) train departures using GTFS static and realtime data.

## Build

- Swift 6.3, macOS 15+, iOS 18+
- `swift build` to build the shared library
- `swift test` to run tests
- Xcode project is generated from `project.yml` via XcodeGen

## Architecture

- `Shared/` — shared library (`PingShared`) used by both iOS and macOS targets
- `iOS/` — iOS app
- `macOS/` — macOS menu bar app
- `Widgets/` — WidgetKit live activity
- `Tests/PingSharedTests/` — tests for the shared library

## Dependencies

- [swift-protobuf](https://github.com/apple/swift-protobuf) — GTFS realtime protobuf parsing
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) — GTFS static ZIP extraction
