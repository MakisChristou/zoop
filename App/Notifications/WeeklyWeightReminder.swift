import Foundation
import Observation
import UserNotifications

/// Scoped weekly reminders continue when a dated goal becomes maintenance.
/// Copy never asserts a result before the latest server weights have been fetched.
@MainActor @Observable final class WeeklyWeightReminder {
    private let now: () -> Date
    private let center: ReminderNotificationClient
    private var input: (ZoopAPI.WeightGoal?, String?) = (nil, nil)
    private var revision = 0
    private var worker: Task<Void, Never>?
    private static let prefix = "snoop.weekly-weight."
    private(set) var error: String?
    init(center: ReminderNotificationClient = .live, now: @escaping () -> Date = Date.init) { self.center = center; self.now = now }
    func update(goal: ZoopAPI.WeightGoal?, scope: String?) {
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
        var desired: [(String, DateComponents, Bool)] = []
        if enabled, let goal, let scope {
            var date = DateComponents()
            let calendar = CutPlan.calendar(timezone: goal.timezone)
            date.timeZone = calendar.timeZone; date.weekday = goal.reminderWeekday
            date.hour = goal.reminderMinute / 60; date.minute = goal.reminderMinute % 60
            desired.append((Self.prefix + scope + ".weekly", date, true))
        }
        let ids = Set(desired.map { $0.0 })
        let pending = await center.pending()
        center.removePending(pending.filter { $0.identifier.hasPrefix(Self.prefix) && !ids.contains($0.identifier) }.map(\.identifier))
        let delivered = await center.delivered()
        center.removeDelivered(delivered.filter { $0.request.identifier.hasPrefix(Self.prefix) && !ids.contains($0.request.identifier) }.map { $0.request.identifier })
        error = nil
        guard let scope else { return }
        for (id, date, repeats) in desired {
            if let existing = pending.first(where: { $0.identifier == id }), let old = existing.trigger as? UNCalendarNotificationTrigger, old.repeats == repeats, old.dateComponents == date { continue }
            let content = UNMutableNotificationContent()
            content.title = "Your weekly weight outlook"
            content.body = "See how this week compares with your goal."
            content.sound = .default; content.threadIdentifier = "snoop.weekly-weight"
            content.userInfo = ["destination": "weeklyWeight", "scope": scope]
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: repeats)
            do { try await center.add(.init(identifier: id, content: content, trigger: trigger)) }
            catch { self.error = "Couldn’t schedule your weekly reminder. Try again." }
        }
    }
}
