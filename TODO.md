# Ping TODO

## To Do

### Now

- Service alerts (final major feature before full scope is complete)

### Next

#### GTFS-Realtime service alerts
FGC publishes a GTFS Realtime Service Alerts feed (`alerts-gtfs_realtime`) with strikes, closures, and disruptions. Add support to:
- Poll the alerts feed alongside trip updates
- Surface active alerts in iOS and macOS (banner/panel)
- Mark affected lines/departures directly in results
- Add a simple line status strip sourced from the same alerts data

### Later

#### Alert UX polish
- Improve severity colors and copy (minor/major/closed)
- Add “last updated” and stale-state handling for alerts

### Release readiness

#### macOS parity (without Live Activity)
- Keep macOS without Live Activity (intentional scope decision)
- Make macOS calendar commute card actionable (same "use this route" behavior as iOS)
- Add quick route actions in macOS menu view (set/swap/clear) without opening Settings
- Align macOS empty/error states and helper copy with iOS wording and behavior
