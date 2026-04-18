import CoreLocation
import SwiftUI

enum StationPickerTarget: String, Identifiable {
    case origin
    case destination

    var id: String { rawValue }
}

struct StationPickerSheet: View {
    @Environment(PingStore.self) private var store
    let stops: [Stop]
    let title: String
    let counterpartStopID: StopID?
    let excludedStopIDs: Set<StopID>
    let onSelect: (Stop) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var compatibleStopIDs: Set<StopID>?
    @State private var isLoadingCompatibility = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredStops: [Stop] {
        stops
            .filter { stop in
                let matchesQuery = trimmedQuery.isEmpty || stop.name.localizedStandardContains(trimmedQuery)
                let matchesCompatibility = compatibleStopIDs.map { $0.contains(stop.id) } ?? true
                let isNotExcluded = !excludedStopIDs.contains(stop.id)
                return matchesQuery && matchesCompatibility && isNotExcluded
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var nearbyStops: [Stop] {
        guard trimmedQuery.isEmpty, let userLocation = store.userLocation else {
            return []
        }

        let user = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        return filteredStops
            .compactMap { stop -> (Stop, CLLocationDistance)? in
                guard let coordinate = stop.coordinate else {
                    return nil
                }

                let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    .distance(from: user)
                return (stop, distance)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(3)
            .map(\.0)
    }

    var body: some View {
        Group {
            if filteredStops.isEmpty && nearbyStops.isEmpty && !trimmedQuery.isEmpty {
                ContentUnavailableView.search(text: trimmedQuery)
            } else if stops.isEmpty {
                ContentUnavailableView(
                    "No stations available",
                    systemImage: "tram",
                    description: Text("Pull to refresh once Ping finishes loading the FGC schedule.")
                )
            } else {
                List {
                    if !nearbyStops.isEmpty {
                        Section("Nearby Stations") {
                            ForEach(nearbyStops) { stop in
                                Button {
                                    onSelect(stop)
                                    dismiss()
                                } label: {
                                    Text(stop.name)
                                        .foregroundStyle(.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Section("Stations") {
                        ForEach(filteredStops) { stop in
                            Button {
                                onSelect(stop)
                                dismiss()
                            } label: {
                                Text(stop.name)
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search station")
        .task {
            await refreshCompatibility()
        }
        .onChange(of: counterpartStopID) { _, _ in
            Task { await refreshCompatibility() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
            if isLoadingCompatibility {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private func refreshCompatibility() async {
        isLoadingCompatibility = true
        compatibleStopIDs = await store.compatibleStopIDs(with: counterpartStopID)
        isLoadingCompatibility = false
    }
}
