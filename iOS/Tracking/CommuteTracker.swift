import Foundation
import SwiftUI
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Commute tracker (manages Live Activity)

/// Centralised state machine for commute tracking.
///
/// Two modes:
///   * **Planning** — `trackedDeparture == nil`. The hero auto-rolls to the next catchable train.
///   * **TrackingLocked** — user tapped *Follow trip*, pinning a specific `tripID`.
///     We keep rendering that trip even if the store drops it from the upcoming list, and we
///     recompute a `phase` (`tracking`, `likelyMissed`, `missed`) so the UI can react.
@MainActor
@Observable
final class CommuteTracker {
    private static let persistedTripIDKey = "ping.trackedTripID"

    /// `true` while a Live Activity is running. Also implies `trackedDeparture != nil`.
    var isTracking = false
    /// Snapshot of the locked trip, refreshed from the store whenever possible.
    var trackedDeparture: LiveDeparture?
    /// Phase derived from the tracked trip + latest walking ETA.
    var phase: TrackingPhase = .planning
    /// Signed slack between now and *leave-by*. Negative when the user is already behind.
    var bufferSeconds: Int = 0
    /// Minutes until the tracked train actually departs, recomputed from wall-clock each tick.
    /// `nil` while planning (no trip locked).
    var minutesUntilDeparture: Int?

    /// Cached walking ETA; private because it's an internal derivation from the store, not
    /// something callers need to reach into.
    @ObservationIgnored private var walkMinutes: Int = 0

    #if canImport(ActivityKit)
    @ObservationIgnored nonisolated(unsafe) private var activity: Activity<PingActivityAttributes>?
    #endif

    // Transition detection so Live Activity alerts only fire when crossing a threshold,
    // never when restoring a persisted trip or on every refresh.
    @ObservationIgnored private var hasSeededAlertState = false
    @ObservationIgnored private var lastAlertPhase: TrackingPhase = .planning
    @ObservationIgnored private var lastAlertMinutesBucket: Int = .max
    @ObservationIgnored private var lastAlertBufferBucket: Int = .max

    private enum AlertTrigger {
        case leaveNow, twoMinutes, missed
    }

    var trackedTripID: String? { trackedDeparture?.tripID }
    var isTrackingLocked: Bool { trackedDeparture != nil }

    func syncWithSystemActivityState() async {
        #if canImport(ActivityKit)
        let activeActivities = Activity<PingActivityAttributes>.activities

        if let activity, activeActivities.contains(where: { $0.id == activity.id }) {
            isTracking = true
            return
        }

        if let adopted = activeActivities.first {
            activity = adopted
            isTracking = true
            return
        }

        activity = nil
        #endif
        isTracking = false
    }

    /// Reconciles the tracker with the latest store snapshot. Safe to call on every refresh or
    /// polled update — it only mutates when the store has something meaningful for the trip we're
    /// locked onto.
    func syncWithStore(_ store: PingStore) async {
        await syncWithSystemActivityState()
        walkMinutes = store.walkingMinutes

        if !isTracking, trackedDeparture != nil {
            // Live Activity was dismissed from outside the app. Clear the lock so the hero goes
            // back to planning instead of rendering a stale card forever.
            trackedDeparture = nil
            phase = .planning
            bufferSeconds = 0
            minutesUntilDeparture = nil
            hasSeededAlertState = false
            Self.clearPersistedTripID()
            return
        }

        if trackedDeparture == nil, isTracking,
            let persistedTripID = Self.loadPersistedTripID(),
            let found = Self.findDeparture(tripID: persistedTripID, in: store)
        {
            trackedDeparture = found
        }

        if let trackedTripID, let updated = Self.findDeparture(tripID: trackedTripID, in: store) {
            trackedDeparture = updated
        }

        if let tracked = trackedDeparture {
            let trigger = recomputePhase(for: tracked)
            await updateLiveActivity(for: tracked, store: store, trigger: trigger)

            // Clean up stale tracking: a Live Activity stuck on "Missed" for minutes is noise.
            // The in-app hero will fall back to planning mode (next catchable train) automatically.
            let secondsPastDeparture = Date().timeIntervalSince(tracked.effectiveDepartureTime)
            if phase == .missed, secondsPastDeparture >= 60 {
                await stop()
            }
        } else {
            phase = .planning
            bufferSeconds = 0
            minutesUntilDeparture = nil
        }
    }

    /// Locks the tracker onto `departure`, starts (or refreshes) the Live Activity, and persists
    /// the trip ID so tracking survives the app being backgrounded or killed.
    func start(departure: LiveDeparture, store: PingStore) async {
        walkMinutes = store.walkingMinutes
        trackedDeparture = departure
        Self.persistTripID(departure.tripID)
        // Seed the transition trackers so the first recompute after a fresh lock never fires
        // a backfill alert. The actual mutation happens inside recomputePhase.
        hasSeededAlertState = false
        _ = recomputePhase(for: departure)

        // While a trip is actively followed, the Live Activity is the alert channel. Cancel
        // any pending commute notifications so the user doesn't get a banner on top of the
        // Dynamic Island / Lock Screen Live Activity alert.
        await Self.cancelPendingCommuteNotifications()

        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        await syncWithSystemActivityState()
        let attrs = liveActivityAttributes(for: departure, store: store)
        let state = contentState(for: departure, store: store)

        if activity != nil {
            await activity?.update(.init(state: state, staleDate: nil))
            isTracking = true
            return
        }

        let requested = try? Activity.request(
            attributes: attrs,
            content: .init(state: state, staleDate: nil)
        )
        activity = requested
        isTracking = requested != nil
        #endif
    }

    /// Replaces the locked trip with the next catchable upcoming departure, or stops tracking if
    /// nothing viable is available. Used by the "Switch to next train" CTA.
    func switchToNextTrain(store: PingStore) async {
        let now = Date()
        let currentTripID = trackedTripID
        let candidate = store.upcomingDepartures.first { candidate in
            candidate.tripID != currentTripID && candidate.effectiveDepartureTime > now
        }

        if let candidate {
            await start(departure: candidate, store: store)
        } else {
            await stop()
        }
    }

    func stop() async {
        trackedDeparture = nil
        phase = .planning
        bufferSeconds = 0
        minutesUntilDeparture = nil
        hasSeededAlertState = false
        Self.clearPersistedTripID()
        #if canImport(ActivityKit)
        await syncWithSystemActivityState()
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
        #endif
        isTracking = false
    }

    // MARK: - Private helpers

    /// Updates `phase` + `bufferSeconds` for `departure` and returns the Live Activity alert
    /// trigger — if any — that this tick crossed. The very first call after `start(...)` always
    /// returns `nil` (seed) so we don't fire backfill alerts when restoring a persisted trip.
    private func recomputePhase(for departure: LiveDeparture) -> AlertTrigger? {
        let now = Date()
        let untilDeparture = departure.effectiveDepartureTime.timeIntervalSince(now)
        let walkSeconds = TimeInterval(walkMinutes * 60)
        bufferSeconds = Int(untilDeparture - walkSeconds)

        if untilDeparture <= 0 {
            phase = .missed
        } else if walkSeconds - untilDeparture > 30 {
            // Can't reach the platform in time even if leaving now (30 s grace).
            phase = .likelyMissed
        } else {
            phase = .tracking
        }

        let freshMinutes = max(0, Int(ceil(untilDeparture / 60)))
        minutesUntilDeparture = freshMinutes
        // Bucket 0 = "leave now or behind", 1 = "still some slack".
        let bufferBucket = bufferSeconds < 30 ? 0 : 1

        defer {
            lastAlertPhase = phase
            lastAlertMinutesBucket = freshMinutes
            lastAlertBufferBucket = bufferBucket
            hasSeededAlertState = true
        }

        guard hasSeededAlertState else { return nil }

        if phase == .missed, lastAlertPhase != .missed {
            return .missed
        }
        if phase != .missed, bufferBucket == 0, lastAlertBufferBucket != 0 {
            return .leaveNow
        }
        if phase != .missed,
           freshMinutes <= 2,
           freshMinutes > 0,
           lastAlertMinutesBucket > 2,
           bufferBucket != 0
        {
            return .twoMinutes
        }
        return nil
    }

    private static func findDeparture(tripID: String, in store: PingStore) -> LiveDeparture? {
        if let next = store.nextDeparture, next.tripID == tripID {
            return next
        }
        return store.upcomingDepartures.first(where: { $0.tripID == tripID })
    }

    private static func persistTripID(_ tripID: String) {
        UserDefaults.standard.set(tripID, forKey: persistedTripIDKey)
    }

    private static func clearPersistedTripID() {
        UserDefaults.standard.removeObject(forKey: persistedTripIDKey)
    }

    private static func loadPersistedTripID() -> String? {
        UserDefaults.standard.string(forKey: persistedTripIDKey)
    }

    /// Cancels any pending scheduled commute notifications. Called when a Live Activity starts
    /// so the user only gets alerted through the activity's own sound/haptic instead of getting
    /// a duplicate banner on top. `NotificationScheduler.syncCommuteNotifications()` re-schedules
    /// on the next scene-phase change, so there's no permanent loss once tracking ends.
    private static func cancelPendingCommuteNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let commuteIDs = pending.map(\.identifier).filter { $0.hasPrefix("ping.commute.") }
        guard !commuteIDs.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: commuteIDs)
    }

    #if canImport(ActivityKit)
    private func liveActivityAttributes(
        for departure: LiveDeparture,
        store: PingStore
    ) -> PingActivityAttributes {
        let destName = store.availableStops
            .first(where: { $0.id == departure.destinationStopID })?.name
            ?? departure.destinationStopID
        return PingActivityAttributes(destinationName: destName, lineName: store.selectedLine)
    }

    private func contentState(
        for departure: LiveDeparture,
        store: PingStore
    ) -> PingActivityAttributes.ContentState {
        let rideMin = max(
            1,
            Int((departure.arrivalTime.timeIntervalSince(departure.scheduledTime) / 60).rounded())
        )
        // Recompute the minutes countdown on every push. The static value on `LiveDeparture` is
        // captured at fetch time and never decrements, which would freeze the Live Activity.
        let untilDeparture = departure.effectiveDepartureTime.timeIntervalSince(Date())
        let freshMinutes = max(0, Int(ceil(untilDeparture / 60)))
        return PingActivityAttributes.ContentState(
            minutesUntilDeparture: freshMinutes,
            walkMinutes: walkMinutes,
            rideMinutes: rideMin,
            departureTime: departure.effectiveDepartureTime,
            arrivalTime: departure.effectiveArrivalTime,
            phase: phase
        )
    }

    private func updateLiveActivity(
        for departure: LiveDeparture,
        store: PingStore,
        trigger: AlertTrigger? = nil
    ) async {
        guard isTracking else {
            return
        }
        let state = contentState(for: departure, store: store)
        let content = ActivityContent(state: state, staleDate: nil)
        if let alert = alertConfiguration(for: trigger, departure: departure) {
            await activity?.update(content, alertConfiguration: alert)
        } else {
            await activity?.update(content)
        }
    }

    private func alertConfiguration(
        for trigger: AlertTrigger?,
        departure: LiveDeparture
    ) -> AlertConfiguration? {
        guard let trigger else { return nil }
        let trainTime = departure.effectiveDepartureTime.formatted(date: .omitted, time: .shortened)
        switch trigger {
        case .leaveNow:
            return AlertConfiguration(
                title: "Leave now",
                body: "\(departure.trainLabel) · \(trainTime)",
                sound: .default
            )
        case .twoMinutes:
            return AlertConfiguration(
                title: "2 min to departure",
                body: "\(departure.trainLabel) · \(trainTime)",
                sound: .default
            )
        case .missed:
            return AlertConfiguration(
                title: "Missed \(departure.trainLabel)",
                body: "Open Ping to switch to the next train",
                sound: .default
            )
        }
    }
    #endif
}
