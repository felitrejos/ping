import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Home tab

struct ContentView: View {
    @Environment(MakoStore.self) private var store
    @State private var tracker = CommuteTracker()
    @State private var showTracking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusBanner
                primaryCard
                if let plan = store.nextCommute {
                    commuteRow(plan)
                }
                trackButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh() }
        .onChange(of: store.nextDeparture) { _, dep in
            guard showTracking, let dep else { return }
            Task { await tracker.update(departure: dep) }
        }
        .fullScreenCover(isPresented: $showTracking) {
            TrackingView(tracker: tracker) {
                Task {
                    await tracker.stop()
                    showTracking = false
                }
            }
            .environment(store)
        }
    }

    // MARK: Status banner

    @ViewBuilder
    private var statusBanner: some View {
        if !store.hasConfiguredRoute {
            NoticeCard(
                title: "Setup needed",
                message: "Choose your origin and destination in Settings.",
                systemImage: "location.fill",
                tint: .blue
            )
        } else if let msg = store.lastErrorMessage {
            NoticeCard(
                title: "Could not refresh",
                message: msg,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }
    }

    // MARK: Primary card

    @ViewBuilder
    private var primaryCard: some View {
        if let dep = store.nextDeparture {
            TrainHeroCard(departure: dep)
        } else if store.hasConfiguredRoute {
            NoTrainsCard()
        }
    }

    // MARK: Commute row

    private func commuteRow(_ plan: CommutePlan) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(plan.calendarEvent.title)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Text("Leave \(plan.recommendedDeparture.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Track button

    @ViewBuilder
    private var trackButton: some View {
        if let dep = store.nextDeparture {
            Button {
                Task {
                    await tracker.start(departure: dep)
                    showTracking = true
                }
            } label: {
                Label("Track Commute", systemImage: "location.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Tracking view (full screen cover)

private struct TrackingView: View {
    @Environment(MakoStore.self) private var store
    let tracker: CommuteTracker
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if let dep = store.nextDeparture {
                TrainHeroCard(departure: dep)
                    .padding(.horizontal, 16)
            }

            Spacer()

            Button(role: .destructive) {
                onStop()
            } label: {
                Label("Stop Tracking", systemImage: "stop.circle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.large)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Commute tracker (manages Live Activity)

@MainActor
@Observable
final class CommuteTracker {
    var isTracking = false

    #if canImport(ActivityKit)
    @ObservationIgnored nonisolated(unsafe) private var activity: Activity<MakoActivityAttributes>?
    #endif

    func start(departure: LiveDeparture) async {
        isTracking = true
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = MakoActivityAttributes(eventTitle: "Commute", trainLabel: departure.trainLabel)
        let state = MakoActivityAttributes.ContentState(
            minutesUntilDeparture: departure.minutesUntilDeparture,
            isDelayed: departure.isDelayed,
            delayMinutes: departure.delayMinutes
        )
        activity = try? Activity.request(
            attributes: attrs,
            content: .init(state: state, staleDate: nil)
        )
        #endif
    }

    func update(departure: LiveDeparture) async {
        guard isTracking else { return }
        #if canImport(ActivityKit)
        let state = MakoActivityAttributes.ContentState(
            minutesUntilDeparture: departure.minutesUntilDeparture,
            isDelayed: departure.isDelayed,
            delayMinutes: departure.delayMinutes
        )
        await activity?.update(.init(state: state, staleDate: nil))
        #endif
    }

    func stop() async {
        isTracking = false
        #if canImport(ActivityKit)
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
        #endif
    }
}

// MARK: - Train hero card

private struct TrainHeroCard: View {
    let departure: LiveDeparture
    @Environment(MakoStore.self) private var store
    @AppStorage(UserSettings.Keys.walkingMinutes) private var walkingMinutes = UserSettings.defaultWalkingMinutes

    private var leaveIn: Int { max(0, departure.minutesUntilDeparture - walkingMinutes) }
    private var rideMin: Int {
        max(1, Int((departure.arrivalTime.timeIntervalSince(departure.scheduledTime) / 60).rounded()))
    }
    private var destinationName: String {
        store.availableStops.first(where: { $0.id == departure.destinationStopID })?.name
            ?? departure.destinationStopID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider().padding(.horizontal, 16)
            heroCountdown
            timelineSection
            Divider().padding(.horizontal, 16)
            statusRow
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var headerRow: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: "tram.fill")
                    .font(.caption.weight(.semibold))
                Text("TO \(destinationName.uppercased())")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
            }
            .foregroundStyle(.blue)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("ARRIVE BY")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(departure.effectiveArrivalTime.formatted(date: .omitted, time: .shortened))
                    .font(.callout.weight(.bold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var heroCountdown: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Leave in")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(leaveIn)")
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
                Text("min")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var timelineSection: some View {
        let total = walkingMinutes + rideMin
        let walkFraction = CGFloat(walkingMinutes) / CGFloat(total)

        return VStack(spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.55))
                        .frame(width: max(24, (geo.size.width - 2) * walkFraction))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                }
            }
            .frame(height: 8)

            HStack {
                Label("\(walkingMinutes) min walk", systemImage: "figure.walk")
                    .foregroundStyle(.blue)
                Spacer()
                Label("\(rideMin) min ride", systemImage: "tram.fill")
                    .foregroundStyle(.green)
            }
            .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(departure.isDelayed ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
            Text(departure.isDelayed ? "Delayed · \(departure.statusText)" : "On time")
                .font(.callout.weight(.medium))
                .foregroundStyle(departure.isDelayed ? .orange : .green)
            Text("·")
                .foregroundStyle(.quaternary)
            Text("departs \(departure.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Supporting views

private struct NoTrainsCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tram.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No upcoming trains")
                .font(.headline)
            Text("Pull to refresh")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct NoticeCard: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
