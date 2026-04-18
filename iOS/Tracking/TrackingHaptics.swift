import SwiftUI

// MARK: - Tracking haptics

/// Emits contextual haptic feedback as the tracked trip crosses meaningful thresholds.
///
/// * `.success` when the user locks onto a trip (*Follow trip*).
/// * `.impact(.heavy)` when slack first runs out — the "leave now" moment.
/// * `.warning` when the departure countdown first dips under 2 minutes while tracking.
/// * `.error` when the tracked trip transitions into `.missed`.
struct TrackingHapticsModifier: ViewModifier {
    enum LeaveNowBucket: Equatable { case idle, onTime, leaveNow }
    enum TwoMinuteBucket: Equatable { case idle, above, underTwo }

    let tracker: CommuteTracker

    func body(content: Content) -> some View {
        content
            .modifier(RouteConfirmedHaptic(isTrackingLocked: tracker.isTrackingLocked))
            .modifier(LeaveNowHaptic(bucket: leaveNowBucket))
            .modifier(TwoMinuteHaptic(bucket: twoMinuteBucket))
            .modifier(MissedHaptic(phase: tracker.phase))
    }

    private var leaveNowBucket: LeaveNowBucket {
        guard tracker.isTrackingLocked else { return .idle }
        return tracker.bufferSeconds > 30 ? .onTime : .leaveNow
    }

    private var twoMinuteBucket: TwoMinuteBucket {
        guard tracker.isTrackingLocked, let minutes = tracker.minutesUntilDeparture else {
            return .idle
        }
        return minutes > 2 ? .above : .underTwo
    }
}

/// One-shot spring "bump" on the hero card when the leave-now threshold first trips.
///
/// Shares its transition detection logic with `TrackingHapticsModifier.leaveNowBucket` so the
/// visual beat lands in sync with the heavy haptic — user feels it and sees it at the same time.
/// Scale goes 1.0 → 1.03 → 1.0 via chained springs; we keep the amplitude small because the
/// hero card is already the largest element on screen and a bigger bump reads as gimmicky.
struct LeaveNowBumpModifier: ViewModifier {
    let tracker: CommuteTracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bumpScale: CGFloat = 1.0

    private var leaveNowBucket: TrackingHapticsModifier.LeaveNowBucket {
        guard tracker.isTrackingLocked else { return .idle }
        return tracker.bufferSeconds > 30 ? .onTime : .leaveNow
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(bumpScale)
            .onChange(of: leaveNowBucket) { oldValue, newValue in
                guard oldValue == .onTime, newValue == .leaveNow else { return }
                // Reduce Motion: keep the haptic (fired by TrackingHapticsModifier) but skip the
                // visual scale. No fallback flash — the existing phase-driven countdown color and
                // the status banner already carry the "you need to move" signal without motion.
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    bumpScale = 1.03
                } completion: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                        bumpScale = 1.0
                    }
                }
            }
    }
}

private struct RouteConfirmedHaptic: ViewModifier {
    let isTrackingLocked: Bool

    func body(content: Content) -> some View {
        content.sensoryFeedback(
            .success,
            trigger: isTrackingLocked,
            condition: { oldValue, newValue in !oldValue && newValue }
        )
    }
}

private struct LeaveNowHaptic: ViewModifier {
    let bucket: TrackingHapticsModifier.LeaveNowBucket

    func body(content: Content) -> some View {
        content.sensoryFeedback(
            .impact(weight: .heavy),
            trigger: bucket,
            condition: { oldValue, newValue in oldValue == .onTime && newValue == .leaveNow }
        )
    }
}

private struct TwoMinuteHaptic: ViewModifier {
    let bucket: TrackingHapticsModifier.TwoMinuteBucket

    func body(content: Content) -> some View {
        content.sensoryFeedback(
            .warning,
            trigger: bucket,
            condition: { oldValue, newValue in oldValue == .above && newValue == .underTwo }
        )
    }
}

private struct MissedHaptic: ViewModifier {
    let phase: TrackingPhase

    func body(content: Content) -> some View {
        content.sensoryFeedback(
            .error,
            trigger: phase,
            condition: { oldValue, newValue in oldValue != .missed && newValue == .missed }
        )
    }
}
