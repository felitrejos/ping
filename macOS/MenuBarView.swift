import SwiftUI

struct MenuBarView: View {
    @Environment(MakoStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            if !store.hasConfiguredRoute {
                MenuNoticeView(
                    title: "Finish setup",
                    message: "Choose your origin and destination.",
                    systemImage: "location.fill"
                )
            } else if let error = store.lastErrorMessage {
                MenuNoticeView(
                    title: "Could not refresh",
                    message: error,
                    systemImage: "exclamationmark.triangle.fill"
                )
            } else {
                trainSection
            }

            if !store.commutePlans.isEmpty {
                Divider()
                commuteSection
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tram.fill")
                .font(.title3)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text("Mako")
                    .font(.headline)
                if let lastUpdated = store.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative)")
                        .font(.caption2)
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
    private var trainSection: some View {
        if store.upcomingTrains.isEmpty {
            Text("No upcoming departures")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                // Hero: first train
                if let next = store.upcomingTrains.first {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(next.minutesUntilDeparture)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("min")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        StatusPill(departure: next)
                    }
                    HStack(spacing: 6) {
                        Text(next.trainLabel)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(next.effectiveDepartureTime, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Following trains — compact rows
                let following = Array(store.upcomingTrains.dropFirst().prefix(3))
                if !following.isEmpty {
                    Divider()
                    ForEach(following) { departure in
                        HStack(spacing: 6) {
                            Text("\(departure.minutesUntilDeparture) min")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .leading)
                            Text(departure.trainLabel)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(departure.effectiveDepartureTime, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private var commuteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Commutes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(store.commutePlans.prefix(3)) { plan in
                HStack(spacing: 6) {
                    Text(plan.calendarEvent.title)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text("Leave \(plan.recommendedDeparture, style: .time)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await store.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                openSettings()
            } label: {
                Text("Settings")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct StatusPill: View {
    let departure: LiveDeparture

    var body: some View {
        Text(departure.statusText)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
