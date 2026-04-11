#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

struct MakoLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MakoActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Text("🚆")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Leave in \(context.state.minutesUntilDeparture)m")
                        .font(.headline)
                    Text("\(context.attributes.trainLabel) \(statusText(for: context.state))")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("🚆")
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading) {
                        Text(context.attributes.eventTitle)
                        Text("Leave in \(context.state.minutesUntilDeparture)m")
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(statusText(for: context.state))
                }
            } compactLeading: {
                Text("\(context.state.minutesUntilDeparture)m")
            } compactTrailing: {
                Text(context.attributes.trainLabel)
            } minimal: {
                Text("🚆")
            }
        }
    }

    private func statusText(for state: MakoActivityAttributes.ContentState) -> String {
        state.isDelayed ? "+\(state.delayMinutes)m" : "On time"
    }
}
#endif
