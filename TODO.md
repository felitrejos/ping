# Ping TODO

## To Do

### Service alerts
FGC publishes a GTFS Realtime Service Alerts feed (`alerts-gtfs_realtime`) with strike notices, line closures, and unexpected disruptions. Add support to:
- Poll the alerts feed alongside trip updates
- Surface active alerts in the menu bar / iOS UI (e.g. a banner)
- Flag departures that may be affected by a disruption

### Static home screen widget
Add a small/medium WidgetKit widget showing next train at a glance (currently only Live Activity exists).

### Map polish
- Show service alerts directly on affected route segments once alerts are supported
