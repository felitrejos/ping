import SwiftUI

struct MenuBarView: View {
    @Environment(MakoStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            divider

            if !store.hasConfiguredRoute {
                noticeRow("Finish setup", "Choose origin and destination in Settings.", "location.fill")
            } else if let error = store.lastErrorMessage {
                noticeRow("Error", error, "exclamationmark.triangle.fill")
            } else if store.upcomingTrains.isEmpty {
                noticeRow("No departures", "Try refreshing.", "calendar")
            } else {
                trainRows
            }

            if !store.commutePlans.isEmpty {
                divider
                commuteRows
            }

            divider
            footerRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 280)
    }

    // MARK: - Rows

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "tram.fill")
                .foregroundStyle(.blue)
            Text("Mako")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.mini)
            } else if let date = store.lastUpdated {
                Text(updatedText(for: date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var trainRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero row
            if let next = store.upcomingTrains.first {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(next.minutesUntilDeparture)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("min")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    pill(next)
                }
                .padding(.top, 4)

                HStack {
                    Text(next.trainLabel)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(next.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
            }

            // Following trains
            let rest = Array(store.upcomingTrains.dropFirst().prefix(3))
            ForEach(rest) { dep in
                Divider().padding(.vertical, 2)
                HStack {
                    Text("\(dep.minutesUntilDeparture) min")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .leading)
                    Text(dep.trainLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(dep.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var commuteRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Commutes")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

            ForEach(store.commutePlans.prefix(3)) { plan in
                HStack {
                    Text(plan.calendarEvent.title)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text("Leave \(plan.recommendedDeparture.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var footerRow: some View {
        HStack {
            Button("Refresh") { Task { await store.refresh() } }
                .font(.caption)
                .buttonStyle(.plain)
            Spacer()
            Button("Settings") { openSettings() }
                .font(.caption)
                .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var divider: some View {
        Divider().padding(.vertical, 2)
    }

    private func pill(_ dep: LiveDeparture) -> some View {
        Text(dep.statusText)
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(dep.isDelayed ? .orange : .green)
            .background(
                (dep.isDelayed ? Color.orange : Color.green).opacity(0.12),
                in: Capsule()
            )
    }

    private func noticeRow(_ title: String, _ message: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(message).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func updatedText(for date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }
}
