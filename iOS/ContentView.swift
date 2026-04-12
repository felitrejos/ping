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
    @State private var departuresExpanded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                pingHeader
                routeSection
                statusBanner
                primaryCard
                upcomingDeparturesSection
                if let plan = nextCalendarCommute {
                    commuteRow(plan)
                }
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
        .onChange(of: store.lastUpdated) { _, _ in
            guard !store.availableStops.isEmpty else { return }
            Task { await prefillStationNames(from: store.availableStops) }
        }
        .task {
            if !store.availableStops.isEmpty {
                await prefillStationNames(from: store.availableStops)
            }
        }
    }

    private var pingHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            headerIcon
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("Ping")
                    .font(.title3.weight(.semibold))
                Text("Never miss your train")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.hasConfiguredDefaultRoute {
                Button(role: .destructive) {
                    clearRouteFields()
                    Task { await store.clearDefaultRoute() }
                } label: {
                    Label("Clear route", systemImage: "xmark.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private var headerIcon: some View {
        Image("PingHeaderLogo")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.white)
    }

    private var routeSection: some View {
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
                selectedName: $selectedOriginName,
                onClear: {
                    Task { await store.setHomeStation(nil) }
                }
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
                selectedName: $selectedDestinationName,
                onClear: {
                    Task { await store.setDestinationStation(nil) }
                }
            ) { stop in
                selectedDestinationName = stop.name
                destinationQuery = ""
                destinationFocused = false
                isEditingDestination = false
                Task { await store.setDestinationStation(stop.id) }
            }
        }
        .padding(.bottom, 6)
    }

    private func clearRouteFields() {
        originQuery = ""
        destinationQuery = ""
        selectedOriginName = nil
        selectedDestinationName = nil
        originResults = []
        destinationResults = []
        originFocused = false
        destinationFocused = false
        isEditingOrigin = false
        isEditingDestination = false
    }

    private func stationInput(
        placeholder: String,
        query: Binding<String>,
        results: Binding<[Stop]>,
        isEditing: Binding<Bool>,
        focused: FocusState<Bool>.Binding,
        selectedName: Binding<String?>,
        onClear: @escaping () -> Void,
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
                        onClear()
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
        let originID = await store.selectedHomeStationID()
        let destID = await store.selectedDestinationStationID()

        if let originID, let name = stops.first(where: { $0.id == originID })?.name {
            selectedOriginName = name
            originQuery = name
        } else if !originFocused {
            selectedOriginName = nil
            originQuery = ""
        }

        if let destID, let name = stops.first(where: { $0.id == destID })?.name {
            selectedDestinationName = name
            destinationQuery = name
        } else if !destinationFocused {
            selectedDestinationName = nil
            destinationQuery = ""
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if !store.hasConfiguredDefaultRoute {
            NoticeCard(
                title: "Choose your origin and destination above.",
                message: nil,
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
        if store.hasConfiguredDefaultRoute, let dep = store.nextDeparture {
            TrainHeroCard(
                departure: dep,
                isTracking: tracker.isTracking,
                onStartTracking: { Task { await tracker.start(departure: dep, store: store) } },
                onStopTracking: { Task { await tracker.stop() } }
            )
        } else if store.hasConfiguredDefaultRoute {
            NoTrainsCard()
        }
    }

    @ViewBuilder
    private var upcomingDeparturesSection: some View {
        let departures = upcomingDepartureRows
        if store.hasConfiguredDefaultRoute, !departures.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Upcoming departures")
                        .font(.headline)
                    Spacer()
                    if departures.count > 3 {
                        Button {
                            departuresExpanded.toggle()
                        } label: {
                            Label(
                                departuresExpanded ? "Collapse" : "Expand",
                                systemImage: departuresExpanded ? "chevron.up" : "chevron.down"
                            )
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

                if departuresExpanded {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(departures) { departure in
                                departureBoardRow(departure)
                                if departure.id != departures.last?.id {
                                    Divider().padding(.leading, 12)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(spacing: 0) {
                        ForEach(departures.prefix(3)) { departure in
                            departureBoardRow(departure)
                            if departure.id != departures.prefix(3).last?.id {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func departureBoardRow(_ departure: LiveDeparture) -> some View {
        let routeCode = departure.trainLabel.split(separator: " ").first.map(String.init) ?? "FGC"

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(routeCode)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 20)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                HStack(spacing: 6) {
                    Text(departure.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))
                    Text("→")
                    Text(departure.effectiveArrivalTime.formatted(date: .omitted, time: .shortened))
                }
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("Leave in")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                CountdownText(targetDate: departure.effectiveDepartureTime, mode: .board)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                if departure.isDelayed {
                    Text("+\(departure.delayMinutes) min")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func commuteRow(_ plan: CommutePlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.calendarEvent.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if let calendarRouteDetail = calendarRouteDetail(for: plan) {
                        Text(calendarRouteDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()
                Text("Leave \(plan.recommendedDeparture.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await applyCommutePlan(plan) }
            } label: {
                Label("Use this route", systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
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

    private func applyCommutePlan(_ plan: CommutePlan) async {
        await store.setHomeStation(plan.originStationID)
        await store.setDestinationStation(plan.destinationStationID)
    }

    private var nextCalendarCommute: CommutePlan? {
        store.commutePlans.first { !isCurrentRoutePlan($0) }
    }

    private var upcomingDepartureRows: [LiveDeparture] {
        guard let nextDeparture = store.nextDeparture else {
            return store.upcomingDepartures
        }

        return store.upcomingDepartures.filter { $0.id != nextDeparture.id }
    }

    private func isCurrentRoutePlan(_ plan: CommutePlan) -> Bool {
        guard let currentOrigin = store.homeStationID, let currentDestination = store.destinationStationID else {
            return false
        }

        return plan.originStationID == currentOrigin && plan.destinationStationID == currentDestination
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
        let walkMin = store.walkingMinutes
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
        let walkMin = store.walkingMinutes
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
    let isTracking: Bool
    let onStartTracking: () -> Void
    let onStopTracking: () -> Void
    @Environment(PingStore.self) private var store

    private var walkMin: Int { store.walkingMinutes }
    private var rideMin: Int {
        max(1, Int((departure.arrivalTime.timeIntervalSince(departure.scheduledTime) / 60).rounded()))
    }
    private var routeCode: String {
        departure.trainLabel.split(separator: " ").first.map(String.init) ?? store.selectedLine
    }
    private var leaveByDate: Date {
        departure.effectiveDepartureTime.addingTimeInterval(TimeInterval(-walkMin * 60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            liveActivityRow
            Divider().padding(.horizontal, 16)
            heroCountdown
            timelineSection
            if departure.isDelayed {
                Divider().padding(.horizontal, 16)
                statusRow
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var heroCountdown: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Leave in")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                HeroCountdownValue(targetDate: leaveByDate)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 5) {
                    Text(departure.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))
                    Text("→")
                        .foregroundStyle(.secondary)
                    Text(departure.effectiveArrivalTime.formatted(date: .omitted, time: .shortened))
                }
                .font(.callout.weight(.semibold))

                Text(routeCode)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 18)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var timelineSection: some View {
        let total = walkMin + rideMin
        let walkFraction = CGFloat(walkMin) / CGFloat(total)

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
                Label("\(walkMin) min walk", systemImage: store.isUsingLiveLocation ? "location.fill" : "figure.walk")
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
                .fill(Color.orange)
                .frame(width: 8, height: 8)
            Text("Delayed · \(departure.statusText)")
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var liveActivityRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isTracking ? "livephoto" : "sparkles")
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 18)

            Text(isTracking ? "Following trip" : "Live Activity")
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 8)

            if isTracking {
                Button(action: onStopTracking) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            } else {
                Button(action: onStartTracking) {
                    Label("Follow trip", systemImage: "livephoto")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Supporting views

private struct CountdownText: View {
    enum Mode {
        case hero
        case board
    }

    let targetDate: Date
    let mode: Mode

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Text(formattedCountdown(from: timeline.date))
        }
    }

    private func formattedCountdown(from now: Date) -> String {
        let remainingSeconds = max(0, Int(targetDate.timeIntervalSince(now)))
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60

        if remainingSeconds >= 3600 {
            return "\(hours)h \(minutes)min"
        }

        switch mode {
        case .hero:
            return "\(minutes)min"
        case .board:
            return "\(minutes)min \(seconds)s"
        }
    }
}

private struct HeroCountdownValue: View {
    let targetDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remainingSeconds = max(0, Int(targetDate.timeIntervalSince(timeline.date)))
            let hours = remainingSeconds / 3600
            let minutes = (remainingSeconds % 3600) / 60

            if remainingSeconds >= 3600 {
                Text("\(hours)h \(minutes)min")
                    .font(.system(size: 50, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(minutes)")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText())
                    Text("min")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct NoTrainsCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tram.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No upcoming trains")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct NoticeCard: View {
    let title: String
    let message: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
