# Ping TODO

## To Do

### Now

- No immediate items (favorite stations + quick switch shipped)

### Next

#### Service alerts
FGC publishes a GTFS Realtime Service Alerts feed (`alerts-gtfs_realtime`) with strike notices, line closures, and unexpected disruptions. Add support to:
- Poll the alerts feed alongside trip updates
- Surface active alerts in the menu bar / iOS UI (e.g. a banner)
- Flag departures that may be affected by a disruption

#### Service status banner
- Add a lightweight line status strip (normal/minor delays/major disruption)
- Reuse Service Alerts feed data so status stays consistent with active alerts

#### GeoTrain map overlay (investigate)
- Check whether FGC exposes real-time train positions ("GeoTrain") in a usable public feed
- If available, render live train markers on the map with direction and freshness

### Later

#### Map polish
- Show service alerts directly on affected route segments once alerts are supported

### Release readiness

#### macOS parity (without Live Activity)
- Keep macOS without Live Activity (intentional scope decision)
- Make macOS calendar commute card actionable (same "use this route" behavior as iOS)
- Add quick route actions in macOS menu view (set/swap/clear) without opening Settings
- Align macOS empty/error states and helper copy with iOS wording and behavior

#### Notifications + permissions audit
- Confirm current notifications scope: iOS leave reminders only (no macOS notification feature for now)
- Ensure notification copy/permission prompts clearly describe current behavior
- Remove remaining runtime warnings around background refresh registration and verify BG task setup on device
- Validate App Store privacy and permission strings against implemented features only
