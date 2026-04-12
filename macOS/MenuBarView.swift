import SwiftUI

struct MenuBarView: View {
    @Environment(PingStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            if !store.hasConfiguredDefaultRoute {
                setupCard
            } else if let dep = store.nextDeparture {
                trainCard(dep)
            } else if store.lastErrorMessage != nil {
                errorCard
            } else {
                emptyCard
            }

            if store.hasConfiguredRoute, let plan = store.nextCommute {
                commuteRow(plan)
            }

            footerRow
        }
        .frame(width: 300)
    }

    // MARK: - Train card

    private func trainCard(_ dep: LiveDeparture) -> some View {
        let walkMin = store.walkingMinutes
        let leaveIn = max(0, dep.minutesUntilDeparture - walkMin)
        let rideMin = max(1, Int((dep.arrivalTime.timeIntervalSince(dep.scheduledTime) / 60).rounded()))

        return VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .top) {
                HStack(spacing: 5) {
                    Image(systemName: "tram.fill")
                        .font(.caption)
                    Text("TO \(destinationName.uppercased())")
                        .font(.caption.weight(.semibold))
                        .tracking(0.5)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ARRIVE BY")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(dep.effectiveArrivalTime.formatted(date: .omitted, time: .shortened))
                        .font(.title2.weight(.bold))
                }
            }

            // Hero countdown
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Leave in")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("\(leaveIn)")
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                Text("min")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            // Timeline
            timeline(walkMin: walkMin, rideMin: rideMin, dep: dep)

            // Status pill
            HStack(spacing: 6) {
                Circle()
                    .fill(dep.isDelayed ? .orange : .green)
                    .frame(width: 8, height: 8)
                Text(dep.isDelayed ? "Delayed · \(dep.statusText)" : "On time")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(dep.isDelayed ? .orange : .green)
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("departs \(dep.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.fill.quaternary, in: Capsule())
        }
        .padding(16)
    }

    // MARK: - Timeline

    private func timeline(walkMin: Int, rideMin: Int, dep: LiveDeparture) -> some View {
        let total = walkMin + rideMin
        let walkFraction = CGFloat(walkMin) / CGFloat(total)

        return VStack(spacing: 4) {
            // Bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    // Walk segment
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.blue.opacity(0.5))
                        .frame(width: max(20, (geo.size.width - 2) * walkFraction))

                    // Train segment
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.green)
                }
            }
            .frame(height: 6)

            // Labels
            HStack {
                HStack(spacing: 3) {
                    Image(systemName: store.isUsingLiveLocation ? "location.fill" : "figure.walk")
                        .font(.system(size: 9))
                    Text("\(walkMin) min")
                }
                .foregroundStyle(.blue)

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 9))
                    Text("\(rideMin) min")
                }
                .foregroundStyle(.green)
            }
            .font(.caption2.weight(.medium))
        }
    }

    // MARK: - Commute row

    private func commuteRow(_ plan: CommutePlan) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 16)
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(plan.calendarEvent.title)
                        .font(.callout)
                        .lineLimit(1)
                    if let detail = calendarRouteDetail(for: plan) {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Text("Leave \(plan.recommendedDeparture.formatted(date: .omitted, time: .shortened))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func calendarRouteDetail(for plan: CommutePlan) -> String? {
        var parts: [String] = []
        if let location = plan.calendarEvent.location, !location.isEmpty {
            parts.append(location)
        }
        if let originName = store.availableStops.first(where: { $0.id == plan.originStationID })?.name {
            parts.append("from \(originName)")
        }
        if let stationName = store.availableStops.first(where: { $0.id == plan.destinationStationID })?.name {
            let nearestResolved = plan.calendarEvent.resolvedStation
            let isFallbackDestination = nearestResolved != nil && nearestResolved != plan.destinationStationID
            if isFallbackDestination {
                parts.append("best reachable station: \(stationName)")
            } else {
                parts.append("destination station: \(stationName)")
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " -> ")
    }

    // MARK: - Footer

    private var footerRow: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 16)
            HStack {
                Spacer()
                Button("Settings") { openSettings() }
                    .font(.callout)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Fallback cards

    private var setupCard: some View {
        fallbackCard("Set route", "Choose origin and destination in Settings.", "location.fill")
    }

    private var errorCard: some View {
        fallbackCard("Could not load", store.lastErrorMessage ?? "", "exclamationmark.triangle.fill")
    }

    private var emptyCard: some View {
        fallbackCard("No trains", "No catchable departures right now.", "tram.fill")
    }

    private func fallbackCard(_ title: String, _ message: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    // MARK: - Helpers

    private var destinationName: String {
        guard let dep = store.nextDeparture else { return "" }
        return store.availableStops.first(where: { $0.id == dep.destinationStopID })?.name ?? dep.destinationStopID
    }
}
