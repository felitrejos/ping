<h1 align="center">Ping</h1>

<p align="center">
  <img src="iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" alt="Ping app icon" width="96" height="96" />
</p>

<p align="center">
  <strong>Never miss your train — FGC commute assistant for iPhone, Mac, and Live Activities</strong>
</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/swift-6.0-F05138?style=flat&logo=swift&logoColor=white" /></a>
  <a href="#"><img src="https://img.shields.io/badge/swiftui-iOS%2026%2B%20%7C%20macOS%2026%2B-0A84FF?style=flat" /></a>
  <a href="#"><img src="https://img.shields.io/badge/data-GTFS%20%2B%20GTFS--RT-1f6feb?style=flat" /></a>
  <a href="#"><img src="https://img.shields.io/badge/license-MIT-24292e?style=flat" /></a>
</p>

<p align="center">
  Local-first commute planning powered by FGC schedule and realtime data
</p>

---

## Product Overview

`Ping` helps you choose a route fast and know exactly when to leave.

- Find the best next train between two FGC stations
- Track upcoming departures and delay-aware leave times
- Save favorite stations for quick route switching
- Get calendar-aware commute suggestions in one tap
- Follow live train positions on your active line
- Receive iPhone leave reminders and Live Activity trip tracking
- See GTFS-Realtime service alerts in iOS and macOS

---

## Quick Start

1. Launch iOS or macOS target from Xcode.
2. Pick origin and destination stations.
3. Tap `Search routes`.
4. Optionally add favorite stations in Settings.
5. Optionally enable location/calendar access for walking ETA and commute suggestions.

---

## Build From Source

Requirements:

- Xcode with iOS 26+ and macOS 26+ SDKs
- `xcodegen`
- `protoc` (only needed when regenerating GTFS Realtime generated code)

```bash
git clone https://github.com/felitrejos/ping.git
cd ping
xcodegen generate
open Ping.xcodeproj
```

Then select `Ping iOS` or `Ping macOS` and run.

---

## Architecture

- Swift + SwiftUI multi-target app (`iOS/`, `macOS/`, `Widgets/`)
- Shared domain and services in `Shared/`
- GTFS static and GTFS-Realtime ingestion
- Dependencies:
  - `SwiftProtobuf`
  - `ZIPFoundation`

If you need to regenerate protobuf models:

```bash
protoc --swift_out=Shared/Generated Proto/gtfs-realtime.proto
```

---

## Project Layout

```text
ping/
├── Shared/              # shared models, services, engine, settings views
├── iOS/                 # iPhone app
├── macOS/               # menu bar app
├── Widgets/             # Live Activity widget
├── Tests/PingSharedTests/
├── Resources/
└── Proto/
```

---

## Testing

Run shared tests:

```bash
swift test
```

---

## Development Notes

`project.yml` is the source of truth for the Xcode project.

Regenerate the project after target/dependency changes:

```bash
xcodegen generate
```

---

## License

MIT
