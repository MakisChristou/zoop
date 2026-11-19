import Foundation
import Observation
import UserNotifications

/// Celebrates fresh, current-day counts once. Cached snapshots never trigger an alert.
@MainActor @Observable final class StepGoalCompletion {
    private struct Day: Codable {
        var target: Int
        var baselinePending = false
        var consumed = false
        var celebrated: Bool?
        var silent: Bool?
        var observedAt: Date
    }
    var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "reminders.stepsCompletionEnabled")
            if enabled && !oldValue, let scope {
                let key = scope + "." + CutPlan.key(clock(), calendar: calendar())
                if var day = days[key] { day.baselinePending = true; days[key] = day; persist() }
                sample = nil
            }
            reconcileSoon()
        }
    }
    private(set) var error: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let center: ReminderNotificationClient
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: () -> Calendar
    private var days: [String: Day]
    private var goal: ZoopAPI.WeightGoal?
    private var scope: String?
    private var sample: StepGoalReminder.Snapshot?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var worker: Task<Void, Never>?
    private static let prefix = "snoop.steps-complete."
    private static let storageKey = "reminders.stepsCompletionDays"

    init(defaults: UserDefaults = .standard, center: ReminderNotificationClient = .live,
         clock: @escaping () -> Date = Date.init, calendar: @escaping () -> Calendar = { .current }) {
        self.defaults = defaults; self.center = center; self.clock = clock; self.calendar = calendar
        enabled = defaults.object(forKey: "reminders.stepsCompletionEnabled") as? Bool ?? true
        days = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([String: Day].self, from: $0) } ?? [:]
    }

    func activate(goal: ZoopAPI.WeightGoal?, scope: String?) {
        if self.scope != scope || self.goal?.dailyStepsGoal != goal?.dailyStepsGoal || self.goal?.active != goal?.active || self.goal?.startedAt != goal?.startedAt {
            sample = nil
        }
        self.goal = goal; self.scope = scope
        observeTarget()
        reconcileSoon()
    }

    func receive(_ sample: StepGoalReminder.Snapshot?) {
        self.sample = sample
        observeTarget()
        reconcileSoon()
    }

    /// Notification delivery and the visible celebration have separate receipts.
    /// A completed goal can be seen for the first time hours after its notification.
    var celebrationKey: String? {
        let now = clock(), calendar = calendar()
        guard let scope, let target = CutTargets.steps(goal: goal, day: now, now: now, calendar: calendar),
              let sample, sample.day == CutPlan.key(now, calendar: calendar), sample.steps >= target else { return nil }
        let key = scope + "." + sample.day
        guard let day = days[key], !day.baselinePending, day.silent != true, day.celebrated != true else { return nil }
        return key
    }

    /// Called only by a visible foreground progress bar after its entrance settles.
    func claimCelebration(_ key: String) -> Bool {
        guard celebrationKey == key, var day = days[key] else { return false }
        day.celebrated = true; days[key] = day; persist()
        return true
    }

    private func observeTarget() {
        let now = clock(), calendar = calendar()
        guard let scope, let target = CutTargets.steps(goal: goal, day: now, now: now, calendar: calendar) else { return }
        let key = scope + "." + CutPlan.key(now, calendar: calendar)
        if var day = days[key] {
            if target < day.target { day.baselinePending = true }
            day.target = target
            days[key] = day
        } else { days[key] = Day(target: target, observedAt: now) }
        persist()
    }

    private func persist() {
        // Retain recent receipts across launches and timezone changes.
        days = days.filter { $0.value.observedAt > clock().addingTimeInterval(-180 * 86400) }
        if let data = try? JSONEncoder().encode(days) { defaults.set(data, forKey: Self.storageKey) }
    }

    private func reconcileSoon() {
        revision &+= 1
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while true {
                let version = revision
                await reconcile(version: version)
                if revision == version { worker = nil; return }
            }
        }
    }
    func settled() async { await worker?.value }

    private func reconcile(version: Int) async {
        let now = clock(), calendar = calendar(), scope = scope
        let dayKey = CutPlan.key(now, calendar: calendar)
        let target = CutTargets.steps(goal: goal, day: now, now: now, calendar: calendar)
        let key = (scope ?? "") + "." + dayKey, id = Self.prefix + key
        let permission = await center.authorization()
        let pending = await center.pending(), delivered = await center.delivered()
        guard version == revision, dayKey == CutPlan.key(clock(), calendar: self.calendar()) else { return }
        let allowed = enabled && scope != nil && target != nil && (permission == .authorized || permission == .provisional)
        center.removePending(pending.filter { $0.identifier.hasPrefix(Self.prefix) && (!allowed || $0.identifier != id) }.map(\.identifier))
        center.removeDelivered(delivered.filter { $0.request.identifier.hasPrefix(Self.prefix) && (!allowed || $0.request.identifier != id) }.map { $0.request.identifier })
        guard let scope, let target, let sample, sample.day == dayKey, sample.steps >= 0,
              var day = days[key], !day.consumed else { return }
        error = nil
        let reached = sample.steps >= target
        if day.baselinePending {
            day.baselinePending = false
            // Editing the goal is not an achievement. Establish a fresh baseline first.
            if reached { day.consumed = true; day.silent = true }
            days[key] = day; persist()
            return
        }
        guard reached else { return }
        // Claim before suspension, preferring a missed alert over a duplicate after a crash.
        day.consumed = true; days[key] = day; persist()
        guard allowed else { return }
        let content = UNMutableNotificationContent()
        content.title = "Steps goal complete"
        content.body = "\(target.formatted()) steps today. Nice work."
        content.sound = .default; content.threadIdentifier = "snoop.steps-goal"
        content.userInfo = ["destination": "steps", "scope": scope, "day": dayKey]
        do {
            try await center.add(.init(identifier: id, content: content, trigger: nil))
            if self.scope != scope || !enabled || CutTargets.steps(goal: goal, day: clock(), now: clock(), calendar: self.calendar()) == nil {
                center.removePending([id]); center.removeDelivered([id])
            }
        } catch {
            days[key]?.consumed = false; persist()
            self.error = "Couldn’t send your goal notification. Try again."
        }
    }
}
