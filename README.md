<h1 align="center">
  Mako
</h1>

<p align="center">
  Mako is a multiplatform FGC commute assistant for iPhone, Mac, and Live Activities.
</p>

<p align="center">
  It combines bundled GTFS static data, FGC GTFS Realtime trip updates, and calendar context to answer one question quickly: when do I need to leave to catch the right train?
</p>

<p align="center">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.0-F05138?style=for-the-badge&logo=swift&logoColor=white">
  <img alt="Platforms" src="https://img.shields.io/badge/Platforms-iOS%2026%2B%20%7C%20macOS%2026%2B-0A84FF?style=for-the-badge">
  <img alt="Status" src="https://img.shields.io/badge/Status-WIP-F59E0B?style=for-the-badge">
  <img alt="Last commit" src="https://img.shields.io/github/last-commit/felitrejos/mako?style=for-the-badge">
</p>

## What is Mako?

Mako is an early-stage native Apple client for commute planning on FGC. It reads local GTFS schedule data, overlays realtime trip updates, checks your next calendar events, and computes a leave-by time based on walking time and buffer settings.

## Current status

Mako is scaffolded and the first implementation pass is in place:

- GTFS static parsing lives in the shared layer
- GTFS Realtime polling and protobuf decoding are wired up
- calendar matching and commute planning are implemented
- macOS menu bar, iOS app, notifications, and Live Activity shells are present

The project still needs full validation in Xcode with bundled FGC assets, real stop IDs, and on-device testing for notifications and Live Activities.

## Features

- parses bundled FGC GTFS static data from a local ZIP
- fetches FGC GTFS Realtime trip updates and keeps the last known snapshot
- matches calendar event locations against known station names
- recommends when to leave based on walking time, buffer time, and realtime delay
- surfaces upcoming departures on macOS, iOS, notifications, and Live Activities

## Installation

Mako is currently set up as an Xcode-driven app project generated from `project.yml`.

Before you run it, make sure:

1. Xcode is installed and selected as the active developer directory
2. you have the bundled FGC GTFS static ZIP in the app target resources as `google_transit.zip`
3. you replace the placeholder stop IDs in `Shared/Models/Constants.swift`
4. you open `Mako.xcodeproj` and let Swift Package Manager resolve dependencies

Dependencies:

- `SwiftProtobuf`
- `ZIPFoundation`

If you need to regenerate the Xcode project:

```bash
xcodegen generate
```

## Overview

Mako is split into a few distinct layers:

- `Shared/Models`: shared app models, constants, and Live Activity attributes
- `Shared/Services`: GTFS static parsing, GTFS Realtime ingestion, and calendar access
- `Shared/Engine`: commute planning logic, refresh orchestration, and shared app state
- `iOS`: iPhone app shell, notifications, and refresh scheduling
- `macOS`: menu bar app and settings surface
- `Widgets`: Live Activity presentation

The shared layer is intended to hold almost all product logic. The app targets mostly render and trigger refreshes.

## Configuration

The main project-specific configuration lives in `Shared/Models/Constants.swift`.

You should replace:

- `PUT_YOUR_HOME_STOP_ID_HERE`
- `PUT_DESTINATION_STOP_ID_HERE`

You may also want to adjust:

- the bundled GTFS asset name if you rename the ZIP
- the FGC realtime feed URL if FGC changes the export endpoint

User-adjustable values such as home station, walking minutes, and buffer minutes are stored through `UserDefaults`.

## GTFS and realtime data

Mako currently expects:

- a bundled FGC GTFS ZIP for static schedule data
- the FGC GTFS Realtime Trip Updates feed for delay data

The realtime service currently resolves the OpenDataSoft records endpoint first, then downloads the protobuf file URL exposed by that endpoint.

To regenerate GTFS Realtime Swift types:

```bash
protoc --swift_out=Shared/Generated Proto/gtfs-realtime.proto
```

## Testing

Shared tests live in `Tests/MakoSharedTests` and cover:

- GTFS parsing and post-midnight times
- GTFS Realtime decoding and snapshot updates
- calendar event resolution
- commute recommendation logic

In this repository state, the most important next validation steps are:

1. run the shared tests from full Xcode
2. add the real FGC ZIP to the app targets
3. test the macOS menu bar flow against live data
4. test iOS notifications and Live Activities on device

## Development notes

- `project.yml` is the source of truth for the Xcode project
- `Mako.xcodeproj` is generated with `xcodegen generate`
- GTFS Realtime Swift types are generated from `Proto/gtfs-realtime.proto`
- generated protobuf Swift is committed so contributors do not need `protoc` just to build

## Roadmap

- validate the current scaffold in full Xcode
- bundle real FGC assets into the targets
- refine station matching and commute selection rules
- harden notification scheduling and background refresh behavior
- finish the Live Activity update loop from realtime changes

## License

No license has been added yet.
