import Foundation
import Observation
import UserNotifications

/// One scoped recurring notification: iOS can deliver without waking the app to compute.
/// Copy never asserts a result before the latest server weights have been fetched.
@MainActor @Observable final class WeeklyWeightReminder {
    private let center: ReminderNotificationClient
    private var input: (SnoopAPI.WeightGoal?, String?) = (nil, nil)
    private var revision = 0
    private var worker: Task<Void, Never>?
    private static let prefix = "snoop.weekly-weight."
    private(set) var error: String?
    init(center: ReminderNotificationClient = .live) { self.center = center }
    func update(goal: SnoopAPI.WeightGoal?, scope: String?) {
        input = (goal, scope); revision &+= 1
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while true {
                let version = revision
                await reconcile()
                if version == revision { worker = nil; return }
            }
        }
    }
    func settled() async { await worker?.value }
    private func reconcile() async {
        let (goal, scope) = input
        let permission = await center.authorization()
        let enabled = goal?.active == true && goal?.reminderEnabled == true && scope != nil && (permission == .authorized || permission == .provisional)
        let id = enabled ? Self.prefix + (scope ?? "") : nil
        let pending = await center.pending()
        center.removePending(pending.filter { $0.identifier.hasPrefix(Self.prefix) && $0.identifier != id }.map(\.identifier))
        let delivered = await center.delivered()
        center.removeDelivered(delivered.filter { $0.request.identifier.hasPrefix(Self.prefix) && $0.request.identifier != id }.map { $0.request.identifier })
        error = nil
        guard let id, let goal, let scope else { return }
        var date = DateComponents()
        date.timeZone = TimeZone(identifier: goal.timezone)
        date.weekday = goal.reminderWeekday
        date.hour = goal.reminderMinute / 60; date.minute = goal.reminderMinute % 60
        if let existing = pending.first(where: { $0.identifier == id }), let trigger = existing.trigger as? UNCalendarNotificationTrigger, trigger.repeats, trigger.dateComponents == date { return }
        let content = UNMutableNotificationContent()
        content.title = "Your weekly weight outlook"
        content.body = "See how this week compares with your goal."
        content.sound = .default; content.threadIdentifier = "snoop.weekly-weight"
        content.userInfo = ["destination": "weeklyWeight", "scope": scope]
        do { try await center.add(.init(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true))) }
        catch { self.error = "Couldn’t schedule your weekly reminder. Try again." }
    }
}
