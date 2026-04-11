import SwiftUI

struct MenuBarView: View {
    @Environment(MakoStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            nextTrainSection
            Divider()
            commuteSection
            Button("Settings") {
                openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(width: 340)
    }

    private var nextTrainSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next train")
                .font(.headline)
            if let departure = store.nextDeparture {
                Text(departure.effectiveDepartureTime, style: .time)
                    .font(.title.bold())
                Text(departure.trainLabel)
                Text(departure.isDelayed ? "+\(departure.delaySeconds / 60) min" : "On time")
                    .foregroundStyle(departure.isDelayed ? .orange : .green)
                ForEach(store.upcomingTrains.prefix(3)) { next in
                    HStack {
                        Text(next.trainLabel)
                        Spacer()
                        Text(next.effectiveDepartureTime, style: .time)
                    }
                    .font(.caption)
                }
            } else {
                Text("No departures found")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var commuteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's commutes")
                .font(.headline)
            if store.commutePlans.isEmpty {
                Text("No commute plans")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.commutePlans) { plan in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.calendarEvent.title)
                        Text("Leave by \(plan.recommendedDeparture.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
