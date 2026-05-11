<h1 align="center">Ping</h1>

<p align="center">
  <img src="iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" alt="Ping app icon" width="96" height="96" />
</p>

<p align="center">
  <strong>Never miss your train or bus. FGC and TMB commute assistant for iPhone and Mac</strong>
</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/swift-6.0-F05138?style=flat&logo=swift&logoColor=white" /></a>
  <a href="#"><img src="https://img.shields.io/badge/swiftui-iOS%2026%2B%20%7C%20macOS%2026%2B-0A84FF?style=flat" /></a>
  <a href="#"><img src="https://img.shields.io/badge/data-GTFS%20%2B%20GTFS--RT%20%2B%20iBus-1f6feb?style=flat" /></a>
  <a href="#"><img src="https://img.shields.io/badge/license-MIT-24292e?style=flat" /></a>
</p>

<p align="center">
  Local-first commute planning powered by FGC and TMB schedule and realtime data
</p>

<p align="center">
  <img src="Resources/screenshots/hero.png" alt="Ping on iOS — map, results, and home screens" width="900" />
</p>

---

## Product Overview

`Ping` helps you choose a route fast and know exactly when to leave.

- Track upcoming departures and delay-aware leave times
- Save favorite stations for quick route switching
- Get calendar-aware commute suggestions and iPhone leave reminders
- Browse TMB bus stops on the map and tap a stop to see upcoming arrivals
- See FGC service alerts in iOS and macOS

---

## Status

Ping is open source and **built to run from Xcode**. There is no App
Store or TestFlight build. That would require a paid Apple Developer Program
license and I'm not paying for it. Until then:

- **iOS**: clone the repo, open in Xcode, and run on your own device or Simulator.
- **macOS**: either run from Xcode, or grab the unsigned `Ping.dmg` built
  locally via `scripts/release-macos.sh` (see [`RELEASE.md`](RELEASE.md)).

---

## Build From Source

Requirements:

- Xcode with iOS 26+ and macOS 26+ SDKs
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen)
- `protoc` (only needed when regenerating GTFS Realtime generated code)

```bash
git clone https://github.com/felitrejos/ping.git
cd ping
xcodegen generate
open Ping.xcodeproj
```

Then select `Ping iOS` or `Ping macOS` and run. The iOS target needs a free
personal Apple ID signed into Xcode to run on a physical device.

### TMB API keys (iOS only)

TMB map stops and iBus arrivals need API keys. Without them the FGC side of
the app works fine, but the TMB map layer stays empty.

1. Copy `iOS/Config/TMBKeys.example.xcconfig` to `iOS/Config/TMBKeys.xcconfig`.
2. Fill in:
   - `TMB_APP_ID_PRIMARY`
   - `TMB_APP_KEY_PRIMARY`
   - `TMB_APP_ID_BACKUP`
   - `TMB_APP_KEY_BACKUP`

`TMBKeys.xcconfig` is gitignored and picked up by the iOS target config.

---

## Quick Start (in-app)

1. Launch iOS or macOS target from Xcode.
2. Pick origin and destination stations.
3. Tap `Search routes`.
4. Optionally add favorite stations in Settings.
5. Enable location/calendar access for walking ETA and commute suggestions.

---

## Architecture

- Swift + SwiftUI multi-target app (`iOS/`, `macOS/`)
- Shared domain and services in `Shared/`
- FGC GTFS static + GTFS-Realtime ingestion
- TMB GTFS static + iBus arrivals ingestion (iOS map)
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

Unsigned macOS DMG build: see [`RELEASE.md`](RELEASE.md).

---

## License

MIT
