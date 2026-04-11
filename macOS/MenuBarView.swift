import SwiftUI

struct MenuBarView: View {
    @Environment(MakoStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !store.hasConfiguredRoute {
                Text("Open Settings to choose your route.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else if let dep = store.nextDeparture {
                trainCard(dep)
            } else if let error = store.lastErrorMessage {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Could not load")
                        .font(.subheadline.weight(.semibold))
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Text("No catchable trains right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            if let plan = store.nextCommute {
                Divider()
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(plan.calendarEvent.title)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text("Leave \(plan.recommendedDeparture.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Settings") { openSettings() }
                    .font(.caption)
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private func trainCard(_ dep: LiveDeparture) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // "Leave in X min"
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("Leave in")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(max(0, dep.minutesUntilDeparture - UserSettings.walkingMinutes()))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("min")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if dep.isDelayed {
                    Text(dep.statusText)
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .foregroundStyle(.orange)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }

            // Train info
            Text(dep.trainLabel)
                .font(.caption.weight(.medium))

            // Departure → Arrival
            HStack(spacing: 4) {
                Text("Departs")
                    .foregroundStyle(.secondary)
                Text(dep.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("Arrives")
                    .foregroundStyle(.secondary)
                Text(dep.effectiveArrivalTime.formatted(date: .omitted, time: .shortened))
            }
            .font(.caption)
        }
    }
}
