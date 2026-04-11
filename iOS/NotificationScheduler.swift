import ActivityKit
import BackgroundTasks
import Foundation
import UserNotifications

@MainActor
final class NotificationScheduler {
    private let engine: CommuteEngine
    private let center: UNUserNotificationCenter
    private var currentActivity: Activity<MakoActivityAttributes>?

    init(
        engine: CommuteEngine,
        center: UNUserNotificationCenter = .current()
    ) {
        self.engine = engine
        self.center = center
    }

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "app.mako.refresh", using: nil) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            Task {
                await self?.handleBackgroundRefresh(task: task)
            }
        }
    }

    func syncCommuteNotifications() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else {
                return
            }

            let plan = try await engine.nextCommute()
            try await cancelStaleNotifications(activePlan: plan)
            guard let plan, let train = plan.trainOptions.first else {
                await endLiveActivity()
                return
            }

            try await scheduleNotification(for: plan, train: train)
            await updateLiveActivity(for: plan, train: train)
            submitBackgroundRefresh()
        } catch {
            submitBackgroundRefresh()
        }
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask) async {
        submitBackgroundRefresh()
        await syncCommuteNotifications()
        task.setTaskCompleted(success: true)
    }

    private func scheduleNotification(for plan: CommutePlan, train: LiveDeparture) async throws {
        let identifier = notificationIdentifier(for: plan)
        let existingIDs = (await center.pendingNotificationRequests()).map(\.identifier)
        guard !existingIDs.contains(identifier) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Mako"
        content.body = "Leave now for \(plan.calendarEvent.title) · Train at \(train.effectiveDepartureTime.formatted(date: .omitted, time: .shortened))"
        content.sound = .default

        let triggerDate = plan.recommendedDeparture.addingTimeInterval(-300)
        let trigger = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: false)
        )
        try await center.add(request)
    }

    private func cancelStaleNotifications(activePlan: CommutePlan?) async throws {
        let pending = await center.pendingNotificationRequests()
        let activeIdentifier = activePlan.map(notificationIdentifier(for:))
        let stale = pending
            .map(\.identifier)
            .filter { identifier in
                identifier.hasPrefix("mako.commute.") && identifier != activeIdentifier
            }
        center.removePendingNotificationRequests(withIdentifiers: stale)
    }

    private func updateLiveActivity(for plan: CommutePlan, train: LiveDeparture) async {
        let minutes = train.minutesUntilDeparture
        guard minutes > 0 else {
            await endLiveActivity()
            return
        }

        guard minutes <= 30 else {
            await endLiveActivity()
            return
        }

        let attributes = MakoActivityAttributes(
            eventTitle: plan.calendarEvent.title,
            trainLabel: train.trainLabel
        )
        let contentState = MakoActivityAttributes.ContentState(
            minutesUntilDeparture: minutes,
            isDelayed: train.isDelayed,
            delayMinutes: train.delaySeconds / 60
        )

        if let currentActivity {
            await currentActivity.update(
                ActivityContent(state: contentState, staleDate: train.effectiveDepartureTime)
            )
        } else {
            currentActivity = try? Activity.request(
                attributes: attributes,
                content: ActivityContent(state: contentState, staleDate: train.effectiveDepartureTime)
            )
        }
    }

    private func endLiveActivity() async {
        guard let currentActivity else {
            return
        }

        await currentActivity.end(nil, dismissalPolicy: .immediate)
        self.currentActivity = nil
    }

    private func submitBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "app.mako.refresh")
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func notificationIdentifier(for plan: CommutePlan) -> String {
        "mako.commute.\(plan.calendarEvent.id).\(Int(plan.calendarEvent.startDate.timeIntervalSince1970))"
    }
}
