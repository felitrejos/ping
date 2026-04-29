import SwiftUI

// MARK: - Train hero card

struct TrainHeroCard: View {
    let departure: LiveDeparture
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
            departureTimingHeader
            heroCountdown
            timelineSection
            if departure.isDelayed {
                Divider().padding(.horizontal, 16)
                delayBanner
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var departureTimingHeader: some View {
        HStack {
            Spacer()
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
        .padding(.bottom, 6)
    }

    private var heroCountdown: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Leave in")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HeroCountdownValue(targetDate: leaveByDate)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
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

    private var delayBanner: some View {
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
}

// MARK: - Countdown text

struct CountdownText: View {
    let targetDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remainingSeconds = CountdownFormatting.remainingSeconds(until: targetDate, now: timeline.date)
            Text(CountdownFormatting.boardText(remainingSeconds: remainingSeconds))
        }
    }
}

private struct HeroCountdownValue: View {
    let targetDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remainingSeconds = CountdownFormatting.remainingSeconds(until: targetDate, now: timeline.date)
            let parts = CountdownFormatting.heroParts(remainingSeconds: remainingSeconds)

            if parts.isLongForm {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(parts.leadingValue)
                        .font(.system(size: 50, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText(countsDown: true))
                        .lineLimit(1)
                    Text(parts.leadingUnit)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(parts.trailingValue ?? "")
                        .font(.system(size: 50, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText(countsDown: true))
                        .lineLimit(1)
                    Text(parts.trailingUnit ?? "")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(parts.leadingValue)
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText(countsDown: true))
                        .lineLimit(1)
                    Text(parts.leadingUnit)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}
