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
  Local-first commute planning using FGC schedule data, realtime trip updates, and calendar context
</p>

---

## What It Does

`Ping` helps you quickly pick an FGC route and decide when to leave.

- Find the best next train between two FGC stations
- See upcoming departures (next 12h) and real-time delay-aware leave times
- Save favorite stations for quick route switching
- Use calendar-aware commute suggestions in one tap
- Follow live train positions on the map for your active line
- Receive iPhone leave reminders and Live Activity trip tracking

---

## Installation

Requirements:

- Xcode with iOS 26+ and macOS 26+ SDKs
- `xcodegen`
- `protoc`

```bash
git clone https://github.com/felitrejos/ping.git
cd ping
xcodegen generate
open Ping.xcodeproj
```

Before running:

1. Let Xcode finish resolving package dependencies.
2. Confirm `google_transit.zip` is included in app resources.
3. Pick an iOS or macOS target and run.

Dependencies:

- `SwiftProtobuf`
- `ZIPFoundation`

---

## Quickstart

1. Launch the app target you want to test (iOS or macOS).
2. Grant calendar/location permissions (or use the in-app enable buttons).
3. Pick origin and destination stations from the station picker.
4. Tap `Search routes` to load trains.
5. (Optional) Add favorites in Settings for faster switching.

---

## Configuration

Project defaults live in:

```text
Shared/Models/Constants.swift
```

User settings are stored with `UserDefaults`:

- origin station
- destination station
- favorite stations
- buffer minutes before departure
- whether to pick the closest FGC station as the origin on app start

Ping starts without a default route. The next-train card appears after both an origin and destination are configured.
You can change stations freely, then tap `Search routes` to refresh results when ready.

---

## GTFS Realtime

The realtime service resolves the FGC OpenDataSoft record endpoint, downloads the protobuf file exposed by that endpoint, and decodes it with SwiftProtobuf.

Generated GTFS Realtime Swift types are committed to the repository so Xcode can build without requiring `protoc` on every machine.

Regenerate them with:

```bash
protoc --swift_out=Shared/Generated Proto/gtfs-realtime.proto
```

---

## Project Layout

```text
ping/
├── Shared/
│   ├── Models/       # shared models, constants, ActivityKit attributes
│   ├── Services/     # GTFS static, GTFS-RT, calendar services
│   ├── Engine/       # commute planning and shared observable app state
│   └── Views/        # shared SwiftUI settings UI
├── iOS/              # iPhone app, notifications, background refresh
├── macOS/            # menu bar app and popover UI
├── Widgets/          # Live Activity widget
├── Tests/            # shared service and engine tests
└── Proto/            # GTFS Realtime proto source
```

---

## Testing

Shared tests cover:

- GTFS parsing and post-midnight times
- GTFS Realtime decoding and snapshot updates
- calendar event resolution
- commute recommendation logic

Run from Xcode.

---

## Development

`project.yml` is the source of truth for the Xcode project.

Regenerate the project after changing target structure:

```bash
xcodegen generate
```

Generated protobuf code lives under:

```text
Shared/Generated/
```

---

## License

MIT
