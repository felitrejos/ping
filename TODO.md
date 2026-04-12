# Ping TODO

## To Do

### Now

#### Upcoming departures board
Build a departures board for the configured route/station showing the next 3-6 trains (not only the very next one), similar to FGC app behavior so users can plan around the next few options.

#### Favorite stations + quick switch
- Let users pin favorite stations (home, uni, work, etc.)
- Add one-tap quick switch actions for common origin/destination pairs
- Keep this as the primary UX instead of separate AM/PM direction presets

### Next

#### Service alerts
FGC publishes a GTFS Realtime Service Alerts feed (`alerts-gtfs_realtime`) with strike notices, line closures, and unexpected disruptions. Add support to:
- Poll the alerts feed alongside trip updates
- Surface active alerts in the menu bar / iOS UI (e.g. a banner)
- Flag departures that may be affected by a disruption

#### Service status banner
- Add a lightweight line status strip (normal/minor delays/major disruption)
- Reuse Service Alerts feed data so status stays consistent with active alerts

### Later

#### Map polish
- Show service alerts directly on affected route segments once alerts are supported
