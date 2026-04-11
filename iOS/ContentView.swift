import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(MakoStore.self) private var store
    @State private var presentedSheet: PresentedSheet?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    statusSection
                    primarySection
                    upcomingTrainsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Mako")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentedSheet = .settings
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .refreshable {
                await store.refresh()
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .settings:
                    NavigationStack {
                        SharedSettingsView()
                    }
                    .presentationDetents([.medium, .large])
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if !store.hasConfiguredRoute {
            SetupNoticeView {
                presentedSheet = .settings
            }
        } else if let message = store.lastErrorMessage {
            InlineNoticeView(
                title: "Could not refresh",
                message: message,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        } else if let lastUpdated = store.lastUpdated {
            Text("Updated \(lastUpdated, style: .relative)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var primarySection: some View {
        if let plan = store.nextCommute, let train = plan.trainOptions.first {
            CommuteHeroView(plan: plan, train: train)
        } else if let departure = store.nextDeparture {
            NextTrainHeroView(departure: departure)
        } else {
            EmptyDashboardView(hasConfiguredRoute: store.hasConfiguredRoute)
        }
    }

    private var upcomingTrainsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Next train")
                    .font(.headline)
                Spacer()
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let dep = store.nextDeparture {
                TrainTileView(departure: dep)
            } else {
                Text(store.hasConfiguredRoute ? "No catchable trains right now." : "Choose an origin and destination to see departures.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private enum PresentedSheet: String, Identifiable {
    case settings

    var id: String {
        rawValue
    }
}

private struct CommuteHeroView: View {
    let plan: CommutePlan
    let train: LiveDeparture

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(plan.calendarEvent.title, systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Leave by")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(plan.recommendedDeparture, style: .time)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }

            HStack(spacing: 10) {
                Label(train.trainLabel, systemImage: "tram.fill")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                DelayBadgeView(departure: train)
            }

            Text("Train at \(train.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassPanelStyle())
    }
}

private struct NextTrainHeroView: View {
    let departure: LiveDeparture

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Next train", systemImage: "tram.fill")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("\(departure.minutesUntilDeparture) min")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .contentTransition(.numericText())

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(departure.trainLabel)
                        .font(.headline)
                    Text(departure.effectiveDepartureTime, style: .time)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                DelayBadgeView(departure: departure)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassPanelStyle())
    }
}

private struct TrainTileView: View {
    let departure: LiveDeparture

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(departure.trainLabel)
                .font(.headline)
                .lineLimit(2)
                .frame(minHeight: 44, alignment: .topLeading)

            Text(departure.effectiveDepartureTime, style: .time)
                .font(.title3.bold())

            HStack {
                Text("\(departure.minutesUntilDeparture) min")
                    .foregroundStyle(.secondary)
                Spacer()
                DelayBadgeView(departure: departure)
            }
        }
        .frame(width: 190, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DelayBadgeView: View {
    let departure: LiveDeparture

    var body: some View {
        Text(departure.statusText)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(departure.isDelayed ? .orange : .green)
            .background(
                (departure.isDelayed ? Color.orange : Color.green).opacity(0.14),
                in: Capsule()
            )
    }
}

private struct SetupNoticeView: View {
    let openSettings: () -> Void

    var body: some View {
        InlineNoticeView(
            title: "Finish setup",
            message: "Choose your origin and destination stations before departures can be shown.",
            systemImage: "location.fill",
            tint: .blue,
            actionTitle: "Open Settings",
            action: openSettings
        )
    }
}

private struct EmptyDashboardView: View {
    let hasConfiguredRoute: Bool

    var body: some View {
        ContentUnavailableView(
            hasConfiguredRoute ? "No commute found" : "Setup needed",
            systemImage: hasConfiguredRoute ? "calendar" : "location",
            description: Text(hasConfiguredRoute ? "Pull to refresh or check your calendar access." : "Mako needs an origin and destination before it can plan departures.")
        )
        .frame(maxWidth: .infinity)
        .padding(24)
        .modifier(GlassPanelStyle())
    }
}

private struct InlineNoticeView: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.glass)
                        .padding(.top, 4)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct GlassPanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
