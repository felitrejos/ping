import SwiftUI

// MARK: - No trains card
//
// Used in `ContentView`'s `primaryCard` when a route has been searched but the store currently
// has no upcoming departures. We lean on `ContentUnavailableView` (iOS 17+) so the visual
// language is consistent with the system: centred icon, bold title, secondary description, and
// — critically — an inline action so the user has something to do besides stare at the card.
//
// The "Refresh" action triggers a manual store refresh. We intentionally don't show a loading
// state inside the empty view: the card will simply re-render with departures once they
// arrive, which feels more responsive than a spinner here.
struct NoTrainsCard: View {
    let onRefresh: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No upcoming trains", systemImage: "tram.fill")
        } description: {
            Text("Service may have wound down for the night, or FGC is between scheduled departures. Pull to refresh once trains start running again.")
        } actions: {
            Button("Refresh", action: onRefresh)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Compact empty state
//
// Drop-in replacement for the small inline "no data" texts inside the map's station / bus
// popovers. `ContentUnavailableView` would balloon those popovers, so we use a compact
// text-only layout. We deliberately omit a leading icon: the popover already has the
// station/bus glyph in its header, and a second SF Symbol next to it just reads as visual
// noise inside such a tight container.
struct CompactEmptyState: View {
    let title: String
    let detail: String?

    init(title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title))
                .font(.subheadline.weight(.medium))
            if let detail {
                Text(LocalizedStringKey(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
