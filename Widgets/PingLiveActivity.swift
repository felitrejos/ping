#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

struct PingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PingActivityAttributes.self) { context in
            // Lock screen / banner presentation
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "tram.fill")
                            .font(.system(size: 10))
                        Text("Take \(context.attributes.lineName)")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.blue)
                    .padding(.leading, 10)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Arrive by")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.state.arrivalTime, style: .time)
                            .font(.subheadline.bold())
                    }
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("Leave in")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(context.state.leaveInMinutes)")
                                .font(.system(size: 26, weight: .heavy, design: .rounded))
                            Text("min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        HStack(spacing: 2) {
                            let total = context.state.walkMinutes + context.state.rideMinutes
                            let walkFrac = CGFloat(context.state.walkMinutes) / CGFloat(max(total, 1))
                            GeometryReader { geo in
                                HStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.blue.opacity(0.6))
                                        .frame(width: max(16, (geo.size.width - 2) * walkFrac))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(.green)
                                }
                            }
                            .frame(height: 6)
                        }
                        HStack {
                            Label("\(context.state.walkMinutes)m walk", systemImage: "figure.walk")
                                .foregroundStyle(.blue)
                            Spacer()
                            Label("\(context.state.rideMinutes)m ride", systemImage: "tram.fill")
                                .foregroundStyle(.green)
                        }
                        .font(.caption2.weight(.medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
                }
            } compactLeading: {
                Label("\(context.state.leaveInMinutes)m", systemImage: "figure.walk")
                    .font(.caption.bold())
            } compactTrailing: {
                HStack(spacing: 2) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 8))
                    Text(context.state.departureTime, style: .time)
                        .font(.caption2)
                }
            } minimal: {
                Text("\(context.state.leaveInMinutes)")
                    .font(.caption.bold())
            }
        }
    }

    private func lockScreenView(context: ActivityViewContext<PingActivityAttributes>) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                HStack(spacing: 4) {
                    Image(systemName: "tram.fill")
                        .font(.caption.weight(.semibold))
                    Text(context.attributes.lineName)
                        .font(.caption.bold())
                    Text("to \(context.attributes.destinationName)")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.blue)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Arrive by")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(context.state.arrivalTime, style: .time)
                        .font(.title3.bold())
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Leave in")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(context.state.leaveInMinutes)")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                Text("min")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 2) {
                let total = context.state.walkMinutes + context.state.rideMinutes
                let walkFrac = CGFloat(context.state.walkMinutes) / CGFloat(max(total, 1))
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.blue.opacity(0.6))
                            .frame(width: max(16, (geo.size.width - 2) * walkFrac))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.green)
                    }
                }
                .frame(height: 6)
            }

            HStack {
                Label("\(context.state.walkMinutes) min walk", systemImage: "figure.walk")
                    .foregroundStyle(.blue)
                Spacer()
                Label("\(context.state.rideMinutes) min ride", systemImage: "tram.fill")
                    .foregroundStyle(.green)
            }
            .font(.caption2.weight(.medium))
        }
        .padding(16)
    }

}
#endif
