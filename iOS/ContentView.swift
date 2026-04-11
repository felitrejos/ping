import SwiftUI

struct ContentView: View {
    @Environment(MakoStore.self) private var store
    @State private var settingsPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    commuteCard
                    upcomingTrainsSection
                }
                .padding()
            }
            .navigationTitle("Mako")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings") {
                        settingsPresented = true
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .refreshable {
                await store.refresh()
            }
            .sheet(isPresented: $settingsPresented) {
                NavigationStack {
                    SharedSettingsView()
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var commuteCard: some View {
        Group {
            if let nextCommute = store.nextCommute, let nextTrain = nextCommute.trainOptions.first {
                VStack(alignment: .leading, spacing: 12) {
                    Text(nextCommute.calendarEvent.title)
                        .font(.title2.bold())
                    Text(nextCommute.recommendedDeparture, style: .time)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    HStack(spacing: 12) {
                        Label(nextTrain.trainLabel, systemImage: "tram.fill")
                        delayBadge(for: nextTrain)
                    }
                    Text("Train at \(nextTrain.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(PrimaryCardGlassStyle())
            } else {
                ContentUnavailableView("No commute found", systemImage: "calendar")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .modifier(PrimaryCardGlassStyle())
            }
        }
    }

    private var upcomingTrainsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming trains")
                .font(.headline)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(store.upcomingTrains) { departure in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(departure.trainLabel)
                                .font(.headline)
                                .lineLimit(2)
                            Text(departure.effectiveDepartureTime, style: .time)
                                .font(.title3.bold())
                            Text("\(departure.minutesUntilDeparture) min")
                                .foregroundStyle(.secondary)
                            delayBadge(for: departure)
                        }
                        .frame(width: 180, alignment: .leading)
                        .padding(16)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func delayBadge(for departure: LiveDeparture) -> some View {
        let delayMinutes = max(0, departure.delaySeconds / 60)
        Text(departure.isDelayed ? "+\(delayMinutes) min" : "On time")
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(departure.isDelayed ? Color.orange.opacity(0.2) : Color.green.opacity(0.2), in: Capsule())
    }
}

private struct PrimaryCardGlassStyle: ViewModifier {
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
