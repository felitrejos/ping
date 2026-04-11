import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Home tab

struct ContentView: View {
    @Environment(PingStore.self) private var store
    @State private var tracker = CommuteTracker()
    @State private var originQuery = ""
    @State private var destinationQuery = ""
    @State private var originResults: [Stop] = []
    @State private var destinationResults: [Stop] = []
    @State private var isEditingOrigin = false
    @State private var isEditingDestination = false
    @State private var selectedOriginName: String?
    @State private var selectedDestinationName: String?
    @FocusState private var originFocused: Bool
    @FocusState private var destinationFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                makoHeader
                routeSection
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
            guard tracker.isTracking, let dep else { return }
            Task { await tracker.update(departure: dep, store: store) }
        }
        .onChange(of: store.availableStops) { _, stops in
            guard !stops.isEmpty else { return }
            Task { await prefillStationNames(from: stops) }
        }
        .task {
            if !store.availableStops.isEmpty {
                await prefillStationNames(from: store.availableStops)
            }
        }
    }

    private var makoHeader: some View {
        VStack(spacing: 2) {
            Text("Ping")
                .font(.largeTitle.bold())
            Text("Never miss your train")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var routeSection: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline dots + line
            VStack(spacing: 0) {
                Circle()
                    .fill(.blue)
                    .frame(width: 10, height: 10)
                    .padding(.top, 30) // label height + gap + center in input
                Rectangle()
                    .fill(.blue.opacity(0.3))
                    .frame(width: 2)
                Circle()
                    .fill(.blue)
                    .frame(width: 10, height: 10)
                    .padding(.bottom, 19)
            }
            .frame(width: 14)

            // Labels + input fields
            VStack(alignment: .leading, spacing: 0) {
                Text("ORIGIN")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                    .padding(.bottom, 4)

                stationInput(
                    placeholder: "Search station",
                    query: $originQuery,
                    results: $originResults,
                    isEditing: $isEditingOrigin,
                    focused: $originFocused,
                    selectedName: $selectedOriginName
                ) { stop in
                    selectedOriginName = stop.name
                    originQuery = ""
                    originFocused = false
                    isEditingOrigin = false
                    Task { await store.setHomeStation(stop.id) }
                }

                Text("DESTINATION")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                stationInput(
                    placeholder: "Search station",
                    query: $destinationQuery,
                    results: $destinationResults,
                    isEditing: $isEditingDestination,
                    focused: $destinationFocused,
                    selectedName: $selectedDestinationName
                ) { stop in
                    selectedDestinationName = stop.name
                    destinationQuery = ""
                    destinationFocused = false
                    isEditingDestination = false
                    Task { await store.setDestinationStation(stop.id) }
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func stationInput(
        placeholder: String,
        query: Binding<String>,
        results: Binding<[Stop]>,
        isEditing: Binding<Bool>,
        focused: FocusState<Bool>.Binding,
        selectedName: Binding<String?>,
        onSelect: @escaping (Stop) -> Void
    ) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                TextField(placeholder, text: query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .autocorrectionDisabled()
                    .focused(focused)
                    .onChange(of: query.wrappedValue) { _, newValue in
                        Task {
                            if newValue.isEmpty {
                                results.wrappedValue = []
                            } else {
                                results.wrappedValue = await store.searchStops(matching: newValue)
                            }
                        }
                    }
                    .onSubmit {
                        isEditing.wrappedValue = false
                    }
                    .onChange(of: focused.wrappedValue) { _, isFocused in
                        if isFocused {
                            isEditing.wrappedValue = true
                            if query.wrappedValue.isEmpty, let name = selectedName.wrappedValue {
                                query.wrappedValue = name
                            }
                        } else {
                            isEditing.wrappedValue = false
                            if let name = selectedName.wrappedValue, query.wrappedValue != name {
                                query.wrappedValue = name
                            }
                        }
                    }
                if focused.wrappedValue && !query.wrappedValue.isEmpty {
                    Button {
                        query.wrappedValue = ""
                        selectedName.wrappedValue = nil
                        results.wrappedValue = []
                    } label: {
                        Image(systemName: "multiply.circle.fill")
                            .foregroundStyle(.placeholder)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

            if isEditing.wrappedValue && !results.wrappedValue.isEmpty {
                VStack(spacing: 0) {
                    ForEach(results.wrappedValue.prefix(5)) { stop in
                        Button {
                            onSelect(stop)
                            focused.wrappedValue = false
                        } label: {
                            HStack {
                                Text(stop.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        if stop.id != results.wrappedValue.prefix(5).last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .padding(.top, 4)
            }
        }
    }

    private func prefillStationNames(from stops: [Stop]) async {
        let originID = await store.selectedHomeStationID() ?? UserSettings.defaultHomeStationID
        let destID = await store.selectedDestinationStationID() ?? UserSettings.defaultDestinationStationID
        if selectedOriginName == nil, let name = stops.first(where: { $0.id == originID })?.name {
            selectedOriginName = name
            originQuery = name
        }
        if selectedDestinationName == nil, let name = stops.first(where: { $0.id == destID })?.name {
            selectedDestinationName = name
            destinationQuery = name
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if !store.hasConfiguredRoute {
            NoticeCard(
                title: "Setup needed",
                message: "Choose your origin and destination above.",
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

    @ViewBuilder
    private var primaryCard: some View {
        if let dep = store.nextDeparture {
            TrainHeroCard(departure: dep)
        } else if store.hasConfiguredRoute {
            NoTrainsCard()
        }
    }

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

    @ViewBuilder
    private var trackButton: some View {
        if let dep = store.nextDeparture {
            if tracker.isTracking {
                Button {
                    Task { await tracker.stop() }
                } label: {
                    Label("Stop Tracking", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Button {
                    Task { await tracker.start(departure: dep, store: store) }
                } label: {
                    Label("Track Train", systemImage: "location.fill")
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
}

// MARK: - Commute tracker (manages Live Activity)

@MainActor
@Observable
final class CommuteTracker {
    var isTracking = false

    #if canImport(ActivityKit)
    @ObservationIgnored nonisolated(unsafe) private var activity: Activity<PingActivityAttributes>?
    #endif

    func start(departure: LiveDeparture, store: PingStore) async {
        isTracking = true
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let destName = store.availableStops.first(where: { $0.id == departure.destinationStopID })?.name
            ?? departure.destinationStopID
        let walkMin = UserSettings.walkingMinutes()
        let rideMin = max(1, Int((departure.arrivalTime.timeIntervalSince(departure.scheduledTime) / 60).rounded()))
        let attrs = PingActivityAttributes(
            destinationName: destName,
            lineName: store.selectedLine
        )
        let state = PingActivityAttributes.ContentState(
            minutesUntilDeparture: departure.minutesUntilDeparture,
            isDelayed: departure.isDelayed,
            delayMinutes: departure.delayMinutes,
            walkMinutes: walkMin,
            rideMinutes: rideMin,
            departureTime: departure.effectiveDepartureTime,
            arrivalTime: departure.effectiveArrivalTime
        )
        activity = try? Activity.request(
            attributes: attrs,
            content: .init(state: state, staleDate: nil)
        )
        #endif
    }

    func update(departure: LiveDeparture, store: PingStore) async {
        guard isTracking else { return }
        #if canImport(ActivityKit)
        let walkMin = UserSettings.walkingMinutes()
        let rideMin = max(1, Int((departure.arrivalTime.timeIntervalSince(departure.scheduledTime) / 60).rounded()))
        let state = PingActivityAttributes.ContentState(
            minutesUntilDeparture: departure.minutesUntilDeparture,
            isDelayed: departure.isDelayed,
            delayMinutes: departure.delayMinutes,
            walkMinutes: walkMin,
            rideMinutes: rideMin,
            departureTime: departure.effectiveDepartureTime,
            arrivalTime: departure.effectiveArrivalTime
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
    @Environment(PingStore.self) private var store
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
