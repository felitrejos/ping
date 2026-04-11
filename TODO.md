# Mako TODO

This tracks what remains from the first three implementation items:

1. Bundle real FGC GTFS data and configure default route.
2. Get Xcode package/build resolution clean.
3. Add editable destination stop settings.

## Done

- Downloaded the current FGC static GTFS ZIP to `Resources/google_transit.zip`.
- Added `Resources/google_transit.zip` as an explicit resource for the iOS and macOS app targets in `project.yml`.
- Regenerated `Mako.xcodeproj` from `project.yml`.
- Moved default route data out of `Constants.swift` and into mutable user settings.
- Set default origin to Volpelleres (`VO`).
- Set default destination to Sarrià (`SR`).
- Added user-default backed destination station storage.
- Added Settings UI for changing both origin and destination stations.
- Updated iOS and macOS UI copy to talk about origin/destination instead of only home station.
- Added lightweight SDK typechecks for the UI-facing iOS and macOS files.

## Still Missing

### 4. Validate Real Route Data

After the app builds, confirm the default route works:

- origin: Volpelleres (`VO`)
- destination: Sarrià (`SR`)

Manual checks:

1. Launch the iOS app.
2. Confirm Settings shows Volpelleres as origin and Sarrià as destination.
3. Pull to refresh.
4. Confirm the upcoming train rail populates from the bundled GTFS data.
5. Repeat in the macOS menu bar app.

If no trains appear, inspect whether `FGCStaticService.departuresBetween(origin:destination:after:)` needs to use platform stop IDs (`VO1`, `VO2`, `SR1`, `SR2`, etc.) instead of parent station IDs (`VO`, `SR`) for stop-time matching.

### 5. Improve Route Settings UX

The current settings UI uses a station search list where each station row opens a menu with:

- Set as origin
- Set as destination

This is functional, but the next UX pass should consider:

- separate origin and destination picker screens
- swap origin/destination action
- recent/favorite stations
- showing line/platform context when multiple child stops exist

### 6. Decide GTFS Update Policy

The ZIP is currently committed as a bundled static asset. Decide whether Mako should:

- keep a committed bundled ZIP only
- support replacing the ZIP manually during development
- download/update static GTFS periodically in-app later

For now, the app expects `google_transit.zip` in the main bundle.

## Do Not Do Yet

- Do not run app simulator UI checks until package resolution/build succeeds.
- Do not run the test suite until the build graph is clean.
- Do not add background refresh or Live Activity debugging until the default static route works.
