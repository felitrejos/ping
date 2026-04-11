import SwiftUI

struct MenuBarView: View {
    @Environment(MakoStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            nextTrainSection
            Divider()
            commuteSection
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "tram.fill")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mako")
                    .font(.headline)
                if let lastUpdated = store.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var nextTrainSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next train")
                .font(.headline)

            if !store.hasConfiguredRoute {
                MenuNoticeView(
                    title: "Finish setup",
                    message: "Choose your origin and destination stations.",
                    systemImage: "location.fill"
                )
            } else if let departure = store.nextDeparture {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(departure.minutesUntilDeparture)")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                        Text("min")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        StatusPill(departure: departure)
                    }

                    Text(departure.trainLabel)
                        .font(.subheadline.weight(.semibold))
                    Text("Train at \(departure.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let error = store.lastErrorMessage {
                MenuNoticeView(
                    title: "Could not refresh",
                    message: error,
                    systemImage: "exclamationmark.triangle.fill"
                )
            } else {
                MenuNoticeView(
                    title: "No departures found",
                    message: "Try refreshing or check your route settings.",
                    systemImage: "calendar"
                )
            }

            ForEach(store.upcomingTrains.dropFirst().prefix(2)) { departure in
                DepartureRow(departure: departure)
            }
        }
    }

    private var commuteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's commutes")
                .font(.headline)

            if store.commutePlans.isEmpty {
                Text("No commute plans")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.commutePlans.prefix(4)) { plan in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.calendarEvent.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("Leave by \(plan.recommendedDeparture.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            Spacer()

            Button("Settings") {
                openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct DepartureRow: View {
    let departure: LiveDeparture

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(departure.trainLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(departure.effectiveDepartureTime, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(departure: departure)
        }
    }
}

private struct StatusPill: View {
    let departure: LiveDeparture

    var body: some View {
        Text(departure.statusText)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(departure.isDelayed ? .orange : .green)
            .background(
                (departure.isDelayed ? Color.orange : Color.green).opacity(0.12),
                in: Capsule()
            )
    }
}

private struct MenuNoticeView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
