import SwiftUI

struct MenuBarView: View {
    @Environment(MakoStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            if !store.hasConfiguredRoute {
                setupCard
            } else if let dep = store.nextDeparture {
                trainCard(dep)
            } else if store.lastErrorMessage != nil {
                errorCard
            } else {
                emptyCard
            }

            if let plan = store.nextCommute {
                commuteRow(plan)
            }

            footerRow
        }
        .frame(width: 300)
    }

    // MARK: - Train card

    private func trainCard(_ dep: LiveDeparture) -> some View {
        let leaveIn = max(0, dep.minutesUntilDeparture - UserSettings.walkingMinutes())

        return VStack(alignment: .leading, spacing: 12) {
            // Header: destination + arrival
            HStack(alignment: .top) {
                HStack(spacing: 5) {
                    Image(systemName: "tram.fill")
                        .font(.caption)
                    Text(destinationName.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(0.5)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("ARRIVE BY")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(dep.effectiveArrivalTime.formatted(date: .omitted, time: .shortened))
                        .font(.title3.weight(.bold))
                }
            }

            // Big countdown
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(leaveIn)")
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                Text("min")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }

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

    // MARK: - Commute row

    private func commuteRow(_ plan: CommutePlan) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 16)
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(plan.calendarEvent.title)
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                Text("Leave \(plan.recommendedDeparture.formatted(date: .omitted, time: .shortened))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
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
        fallbackCard("Setup needed", "Open Settings to choose your route.", "location.fill")
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
