# Ping TODO

## Done

- Downloaded the current FGC static GTFS ZIP to `Resources/google_transit.zip`.
- Added `Resources/` as a resource build phase for iOS and macOS targets in `project.yml`.
- Regenerated `Ping.xcodeproj` from `project.yml`.
- Moved default route data out of `Constants.swift` and into mutable user settings.
- Set default origin to Volpelleres (`VO`), default destination to Sarrià (`SR`).
- Added user-default backed origin/destination station storage.
- Built Settings UI with Form layout, Picker dropdowns for station selection, walking time stepper, and calendar access status.
- Updated iOS and macOS UI to use origin/destination terminology.
- Fixed GTFS parent/child stop ID resolution — `departuresBetween` now expands parent station IDs (e.g. `VO`) into platform-level child IDs (e.g. `VO1`, `VO2`) so stop_times.txt matches work.
- Station picker only shows parent stations, not individual platforms.
- Calendar permission is requested automatically on first launch via `PingStore.start()`.
- Fixed all Swift 6 concurrency errors (Sendable closures, type inference, ActivityKit).
- Fixed widget target module name collision and missing ZIPFoundation dependency.
- All 11 tests passing (static, realtime, calendar, engine).

## Still To Do

### 1. On-device validation

Launch the app and confirm the Volpelleres → Sarrià route shows real departures:

1. Launch the macOS menu bar app.
2. Verify trains appear under "Next train" and "Upcoming trains".
3. Open Settings and confirm origin/destination dropdowns work.
4. Repeat on iOS simulator or device.

### 2. Improve Settings UX (polish)

- Swap origin/destination action
- Recent/favorite stations
- Show line/platform context when multiple child stops exist

### 3. Decide GTFS Update Policy

The ZIP is currently committed as a bundled static asset. Decide whether to:

- keep a committed bundled ZIP only
- support replacing the ZIP manually during development
- download/update static GTFS periodically in-app later

### 4. Static Home Screen Widget

Only the LiveActivity widget exists. Add a small/medium WidgetKit widget showing next train at a glance.

### 5. On-device Testing

- Notifications: verify local notification scheduling and dedupe
- Live Activity: verify start, update, and end lifecycle
- Background refresh: verify `app.ping.refresh` task registration and execution
