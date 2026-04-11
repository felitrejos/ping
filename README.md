<h1 align="center">Mako</h1>

<p align="center">
  <strong>Multiplatform FGC commute assistant for iPhone, Mac, and Live Activities</strong>
</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/swift-6.0-F05138?style=flat&logo=swift&logoColor=white" /></a>
  <a href="#"><img src="https://img.shields.io/badge/swiftui-iOS%2026%2B%20%7C%20macOS%2026%2B-0A84FF?style=flat" /></a>
  <a href="#"><img src="https://img.shields.io/badge/data-GTFS%20%2B%20GTFS--RT-1f6feb?style=flat" /></a>
  <a href="#"><img src="https://img.shields.io/badge/status-WIP-F59E0B?style=flat" /></a>
</p>

<p align="center">
  Local-first commute planning using FGC schedule data, realtime trip updates, and calendar context
</p>

---

## What It Does

`Mako` helps you decide when to leave home for an upcoming FGC commute.

- Parse bundled FGC GTFS static data from a local ZIP
- Fetch FGC GTFS Realtime Trip Updates and keep the last known snapshot
- Match calendar event locations against known FGC station names
- Compute leave-by times from walking minutes, buffer minutes, and realtime delays
- Show upcoming departures in a macOS menu bar app
- Show commute plans and next trains in an iOS app
- Schedule leave-now notifications for upcoming calendar commutes
- Start and update Live Activities for tracked departures

---

## Installation

Requires: Xcode with iOS 26+ and macOS 26+ SDKs, `xcodegen`, `protoc`

```bash
git clone https://github.com/felitrejos/mako.git
cd mako
xcodegen generate
open Mako.xcodeproj
```

Before running the app:

1. Add the FGC GTFS static ZIP to the app target resources as `google_transit.zip`.
2. Replace the placeholder stop IDs in `Shared/Models/Constants.swift`.
3. Let Xcode resolve Swift Package Manager dependencies.
4. Run the macOS or iOS target from Xcode.

Dependencies:

- `SwiftProtobuf`
- `ZIPFoundation`

---

## Quickstart

```bash
xcodegen generate
open Mako.xcodeproj
```

1. Open the project in Xcode.
2. Select the macOS target to test the menu bar app.
3. Select the iOS target to test the main commute view.
4. Grant calendar access when prompted.
5. Configure your home station and walking time in Settings.

The project is still early. Notifications, background refresh, and Live Activities should be validated on device.

---

## Configuration

Project defaults live in:

```text
Shared/Models/Constants.swift
```

Replace:

- `PUT_YOUR_HOME_STOP_ID_HERE`
- `PUT_DESTINATION_STOP_ID_HERE`

User settings are stored with `UserDefaults`:

- home station
- walking minutes to station
- buffer minutes before departure

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
mako/
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

Run from Xcode for now. The local command-line environment used to scaffold this project did not have a full Xcode developer directory selected, so `xcodebuild` validation has not been completed yet.

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

## Status

Mako is currently a scaffolded WIP.

- real FGC stop IDs still need to be configured
- the static GTFS ZIP still needs to be bundled into the app targets
- macOS and iOS flows need full Xcode validation
- notification scheduling needs device testing
- Live Activity start/update/end behavior needs device testing

---

## License

No license has been added yet.
