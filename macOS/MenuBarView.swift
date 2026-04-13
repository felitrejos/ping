import SwiftUI
#if os(macOS)
import AppKit
#endif

struct MenuBarView: View {
    @Environment(PingStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @AppStorage(UserSettings.Keys.menuBarSleepMode) private var isMenuBarSleeping = false
    @State private var activeFavoritePopoverStopID: StopID?
    @State private var showsUpcomingDepartures = false

    var body: some View {
        VStack(spacing: 0) {
            primarySection

            if store.nextDeparture != nil, !upcomingDepartureRowsForDisplay.isEmpty {
                upcomingDeparturesSection
            }

            if !actionableServiceAlerts.isEmpty {
                serviceAlertsSection
            }

            if hasFavoriteStationsSection {
                favoriteStationsSection
            }

            calendarSection
            footerRow
        }
        .frame(width: 320)
    }

    // MARK: - Primary section

    @ViewBuilder
    private var primarySection: some View {
        if !store.hasConfiguredDefaultRoute {
            setupCard
        } else if isMenuBarSleeping {
            if let dep = store.nextDeparture {
                sleepCard(dep)
            } else {
                sleepingFallbackCard
            }
        } else if let dep = store.nextDeparture {
            trainCard(dep)
        } else if store.lastErrorMessage != nil {
            errorCard
        } else {
            emptyCard
        }
    }

    // MARK: - Train card

    private func trainCard(_ dep: LiveDeparture) -> some View {
        let walkMin = store.walkingMinutes
        let leaveByDate = dep.effectiveDepartureTime.addingTimeInterval(TimeInterval(-walkMin * 60))
        let rideMin = max(1, Int((dep.arrivalTime.timeIntervalSince(dep.scheduledTime) / 60).rounded()))
        let routeCode = dep.trainLabel.split(separator: " ").first.map(String.init) ?? store.selectedLine

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                HStack(spacing: 5) {
                    Text(routeTitle)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 5) {
                        Text(dep.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))
                        Text("→")
                            .foregroundStyle(.secondary)
                        Text(dep.effectiveArrivalTime.formatted(date: .omitted, time: .shortened))
                    }
                    .font(.callout.weight(.semibold))

                    Text(routeCode)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 18)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Leave in")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                MenuBarHeroCountdownValue(targetDate: leaveByDate)
            }

            timeline(walkMin: walkMin, rideMin: rideMin)

            if dep.isDelayed {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                    Text("Delayed · \(dep.statusText)")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.fill.quaternary, in: Capsule())
            }
        }
        .padding(16)
    }

    private func sleepCard(_ dep: LiveDeparture) -> some View {
        let routeCode = dep.trainLabel.split(separator: " ").first.map(String.init) ?? store.selectedLine

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(routeTitle)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .lineLimit(1)
                Spacer()
                Label("Sleeping", systemImage: "moon.zzz")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(routeCode)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 18)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(dep.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()

                Text("→")
                    .foregroundStyle(.secondary)

                Text(dep.effectiveArrivalTime.formatted(date: .omitted, time: .shortened))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Text("Live countdown is paused while Sleep mode is on.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    // MARK: - Timeline

    private func timeline(walkMin: Int, rideMin: Int) -> some View {
        let total = walkMin + rideMin
        let walkFraction = CGFloat(walkMin) / CGFloat(max(total, 1))

        return VStack(spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.blue.opacity(0.5))
                        .frame(width: max(20, (geo.size.width - 2) * walkFraction))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(.green)
                }
            }
            .frame(height: 6)

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

    // MARK: - Service alerts

    private var serviceAlertsSection: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 10) {
                if let primaryAlert = actionableServiceAlerts.max(by: { severityRank($0.severity) < severityRank($1.severity) }) {
                    alertCard(
                        title: primaryAlert.title,
                        message: primaryAlert.details,
                        severity: primaryAlert.severity
                    )
                }

                if !lineStatusRows.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(lineStatusRows) { row in
                                HStack(spacing: 6) {
                                    Text(row.line)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 18)
                                        .background(.blue, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                                    Text(severityLabel(row.severity))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(severityColor(row.severity))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(.fill.quaternary, in: Capsule())
                            }
                        }
                    }
                }

                if let lastUpdated = store.serviceAlertsLastUpdated {
                    AlertsFreshnessCaptionMac(lastUpdated: lastUpdated)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func alertCard(title: String, message: String?, severity: ServiceAlertSeverity) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(severityColor(severity))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(10)
        .background(severityColor(severity).opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
    }

    private var actionableServiceAlerts: [ServiceAlert] {
        store.activeServiceAlerts.filter { $0.severity != .info }
    }

    private var lineStatusRows: [LineStatusRow] {
        var severityByLine: [String: ServiceAlertSeverity] = [:]

        for alert in actionableServiceAlerts {
            for line in alert.affectedLines {
                if let current = severityByLine[line] {
                    if severityRank(alert.severity) > severityRank(current) {
                        severityByLine[line] = alert.severity
                    }
                } else {
                    severityByLine[line] = alert.severity
                }
            }
        }

        return severityByLine
            .map { LineStatusRow(line: $0.key, severity: $0.value) }
            .sorted { $0.line.localizedStandardCompare($1.line) == .orderedAscending }
    }

    private func severityRank(_ severity: ServiceAlertSeverity) -> Int {
        switch severity {
        case .info:
            0
        case .minor:
            1
        case .major:
            2
        case .closure:
            3
        }
    }

    private func severityColor(_ severity: ServiceAlertSeverity) -> Color {
        switch severity {
        case .info:
            .blue
        case .minor:
            .yellow
        case .major:
            .orange
        case .closure:
            .red
        }
    }

    private func severityLabel(_ severity: ServiceAlertSeverity) -> String {
        switch severity {
        case .info:
            "Info"
        case .minor:
            "Minor"
        case .major:
            "Major"
        case .closure:
            "Closure"
        }
    }

    // MARK: - Favorite stations

    private var hasFavoriteStationsSection: Bool {
        !store.favoriteStations.isEmpty
    }

    private var favoriteStationsSection: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Favorite stations")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                if !store.favoriteStations.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(store.favoriteStations) { stop in
                                favoriteQuickChip(for: stop)
                            }
                        }
                    }
                } else {
                    Text("Add favorite stations in Settings for quick route switching.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func favoriteQuickChip(for stop: Stop) -> some View {
        Button {
            activeFavoritePopoverStopID = stop.id
        } label: {
            Text(stop.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.fill.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: favoritePopoverBinding(for: stop.id),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await store.setHomeStation(stop.id) }
                    activeFavoritePopoverStopID = nil
                } label: {
                    Text("Set as origin")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .controlSize(.large)

                Button {
                    Task { await store.setDestinationStation(stop.id) }
                    activeFavoritePopoverStopID = nil
                } label: {
                    Text("Set as destination")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .controlSize(.large)
            }
            .frame(minWidth: 180)
            .padding()
        }
    }

    private func favoritePopoverBinding(for stopID: StopID) -> Binding<Bool> {
        Binding(
            get: { activeFavoritePopoverStopID == stopID },
            set: { isPresented in
                activeFavoritePopoverStopID = isPresented ? stopID : nil
            }
        )
    }

    // MARK: - Upcoming departures

    private var upcomingDepartureRowsForDisplay: [LiveDeparture] {
        let sortedUpcoming = store.upcomingDepartures.sorted {
            $0.effectiveDepartureTime < $1.effectiveDepartureTime
        }

        guard let nextDeparture = store.nextDeparture else {
            return Array(sortedUpcoming.prefix(10))
        }

        return Array(sortedUpcoming.filter { $0.id != nextDeparture.id }.prefix(10))
    }

    private var upcomingDeparturesSection: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsUpcomingDepartures.toggle()
                    }
                } label: {
                    HStack {
                        Text(showsUpcomingDepartures ? "Hide upcoming departures" : "Show upcoming departures")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: showsUpcomingDepartures ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showsUpcomingDepartures {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(upcomingDepartureRowsForDisplay) { departure in
                                upcomingDepartureRow(departure)
                                if departure.id != upcomingDepartureRowsForDisplay.last?.id {
                                    Divider().padding(.leading, 12)
                                }
                            }
                        }
                    }
                    .frame(height: upcomingDeparturesListHeight)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var upcomingDeparturesListHeight: CGFloat {
        let rowHeight: CGFloat = 40
        let cappedCount = min(upcomingDepartureRowsForDisplay.count, 4)
        return max(44, CGFloat(cappedCount) * rowHeight)
    }

    private func upcomingDepartureRow(_ departure: LiveDeparture) -> some View {
        let routeCode = departure.trainLabel.split(separator: " ").first.map(String.init) ?? store.selectedLine
        let leaveByDate = departure.effectiveDepartureTime.addingTimeInterval(TimeInterval(-store.walkingMinutes * 60))

        return HStack(spacing: 10) {
            Text(routeCode)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 18)
                .background(.blue, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack(spacing: 6) {
                Text(departure.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))
                Text("→")
                    .foregroundStyle(.secondary)
                Text(departure.effectiveArrivalTime.formatted(date: .omitted, time: .shortened))
            }
            .font(.caption.monospacedDigit().weight(.semibold))

            Spacer()

            MenuBarCountdownText(targetDate: leaveByDate)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    // MARK: - Calendar section

    private var calendarSection: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 8) {
                Text("Calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if !store.calendarAuthorization.isAuthorized {
                    Text("Enable calendar access in Settings to get commute suggestions from your upcoming events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let plan = nextCalendarCommute {
                    commuteRow(plan)
                } else {
                    Text("No upcoming calendar commutes. Add events with a location to see route suggestions here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func commuteRow(_ plan: CommutePlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.calendarEvent.title)
                        .font(.callout)
                        .lineLimit(1)
                    if let detail = CommutePresentation.calendarRouteDetail(
                        for: plan,
                        availableStops: store.availableStops
                    ) {
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

            Button {
                applyCommutePlan(plan)
            } label: {
                Label("Use this route", systemImage: "arrow.triangle.branch")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func applyCommutePlan(_ plan: CommutePlan) {
        Task {
            await store.setRoute(origin: plan.originStationID, destination: plan.destinationStationID)
        }
    }

    private var nextCalendarCommute: CommutePlan? {
        store.commutePlans.first { !isCurrentRoutePlan($0) }
    }

    private func isCurrentRoutePlan(_ plan: CommutePlan) -> Bool {
        guard let currentOrigin = store.homeStationID, let currentDestination = store.destinationStationID else {
            return false
        }

        return plan.originStationID == currentOrigin && plan.destinationStationID == currentDestination
    }

    // MARK: - Footer

    private var footerRow: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 16)
            HStack {
                Button("Settings") {
                    openSettingsWindow()
                }
                    .font(.callout)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Quit") {
                    terminateApp()
                }
                .font(.callout)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func openSettingsWindow() {
        #if os(macOS)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #endif
        openSettings()
    }

    private func terminateApp() {
        #if os(macOS)
        NSApp.terminate(nil)
        #endif
    }

    // MARK: - Fallback cards

    private var setupCard: some View {
        fallbackCard("Set route", "Choose origin and destination in Settings.", "location.fill")
    }

    private var sleepingFallbackCard: some View {
        fallbackCard("Sleep mode on", "Live countdown is paused. Wake from Settings anytime.", "moon.zzz.fill")
    }

    private var errorCard: some View {
        fallbackCard("Could not refresh", store.lastErrorMessage ?? "", "exclamationmark.triangle.fill")
    }

    private var emptyCard: some View {
        fallbackCard("No upcoming trains", "No upcoming trains right now.", "tram.fill")
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
        if let dep = store.nextDeparture {
            return store.availableStops.first(where: { $0.id == dep.destinationStopID })?.name ?? dep.destinationStopID
        }
        guard let destinationID = store.destinationStationID else {
            return "Destination"
        }
        return store.availableStops.first(where: { $0.id == destinationID })?.name ?? destinationID
    }

    private var originName: String {
        guard let originID = store.homeStationID else {
            return "Origin"
        }

        return store.availableStops.first(where: { $0.id == originID })?.name ?? originID
    }

    private var routeTitle: String {
        "\(originName) → \(destinationName)"
    }
}

private struct AlertsFreshnessCaptionMac: View {
    let lastUpdated: Date
    private let staleThreshold: TimeInterval = 15 * 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let isStale = timeline.date.timeIntervalSince(lastUpdated) >= staleThreshold

            HStack(spacing: 0) {
                Text("Updated ")
                Text(lastUpdated, style: .relative)
                if isStale {
                    Text(" · may be outdated")
                }
            }
            .font(.caption2)
            .foregroundStyle(isStale ? .orange : .secondary)
        }
    }
}

private struct LineStatusRow: Identifiable {
    let line: String
    let severity: ServiceAlertSeverity

    var id: String {
        line
    }
}

private struct MenuBarCountdownText: View {
    let targetDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remainingSeconds = CountdownFormatting.remainingSeconds(until: targetDate, now: timeline.date)
            Text(CountdownFormatting.boardText(remainingSeconds: remainingSeconds))
        }
    }
}

private struct MenuBarHeroCountdownValue: View {
    let targetDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remainingSeconds = CountdownFormatting.remainingSeconds(until: targetDate, now: timeline.date)
            let parts = CountdownFormatting.heroParts(remainingSeconds: remainingSeconds)
            countdownBody(parts: parts)
        }
    }

    @ViewBuilder
    private func countdownBody(parts: HeroCountdownParts) -> some View {
        if parts.isLongForm {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(parts.leadingValue)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(parts.leadingUnit)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(parts.trailingValue ?? "")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(parts.trailingUnit ?? "")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(parts.leadingValue)
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)

                Text(parts.leadingUnit)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}
