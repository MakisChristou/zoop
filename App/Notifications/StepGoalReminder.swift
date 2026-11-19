import Foundation
import Observation
import UserNotifications

/// One current-day snapshot reminder, refreshed by sync; never a background timer.
@MainActor @Observable final class StepGoalReminder {
    struct Snapshot: Codable, Equatable, Sendable {
        let day: String
        let steps: Int
    }
    typealias Loader = @Sendable (String, Date) async throws -> Snapshot?
    var enabled: Bool { didSet { defaults.set(enabled, forKey: "reminders.stepsEnabled"); reconcileSoon() } }
    var minute: Int { didSet { defaults.set(minute, forKey: "reminders.stepsMinute"); reconcileSoon() } }
    let completion: StepGoalCompletion
    private(set) var error: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let center: ReminderNotificationClient
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: () -> Calendar
    @ObservationIgnored private let loader: Loader
    @ObservationIgnored private var goal: ZoopAPI.WeightGoal?
    @ObservationIgnored private var scope: String?
    @ObservationIgnored private var device = ""
    @ObservationIgnored private var connection = ""
    @ObservationIgnored private var snapshot: Snapshot?
    @ObservationIgnored private var receipts: [String: Date]
    @ObservationIgnored private var lastFetch: Date?
    @ObservationIgnored private var fetch: Task<Void, Never>?
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var worker: Task<Void, Never>?
    private static let prefix = "snoop.steps-goal."

    init(defaults: UserDefaults = .standard, center: ReminderNotificationClient = .live, clock: @escaping () -> Date = Date.init, calendar: @escaping () -> Calendar = { .current }, loader: @escaping Loader = { device, date in try await StepGoalReminder.load(device, date) }) {
        self.defaults = defaults; self.center = center; self.clock = clock; self.calendar = calendar; self.loader = loader
        completion = StepGoalCompletion(defaults: defaults, center: center, clock: clock, calendar: calendar)
        enabled = defaults.object(forKey: "reminders.stepsEnabled") as? Bool ?? true
        minute = defaults.object(forKey: "reminders.stepsMinute") as? Int ?? 22 * 60
        receipts = defaults.data(forKey: "reminders.stepsReceipts").flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
    }
    nonisolated private static func load(_ device: String, _ date: Date) async throws -> Snapshot? {
        let data = try await ZoopAPI.steps(deviceId: device, day: date)
        // A zero-filled response alone cannot distinguish a quiet day from no sensor data.
        if data.walking == 0 && data.total == 0 {
            let days = try await ZoopAPI.days(deviceId: device, limit: 2)
            guard days.contains(where: { $0.day == data.day }) else { return nil }
        }
        return .init(day: data.day, steps: data.walking)
    }
    func activate(goal: ZoopAPI.WeightGoal?, device: String, scope: String?) {
        if self.scope != scope || self.device != device || connection != Settings.connectionID {
            fetch?.cancel(); fetch = nil; request = UUID(); lastFetch = nil; snapshot = nil
            self.scope = scope; self.device = device; connection = Settings.connectionID
            if let scope, let data = defaults.data(forKey: "stepsReminder." + scope) { snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) }
        }
        let changedTarget = self.goal?.dailyStepsGoal != goal?.dailyStepsGoal
        self.goal = goal
        completion.activate(goal: goal, scope: scope)
        reconcileSoon(); refresh(force: changedTarget)
    }
    func refresh(force: Bool = false) {
        let now = clock(), calendar = calendar()
        guard enabled || completion.enabled, let scope, !device.isEmpty, CutTargets.steps(goal: goal, day: now, now: now, calendar: calendar) != nil else { reconcileSoon(); return }
        guard force || lastFetch.map({ now.timeIntervalSince($0) >= 60 }) != false else { return }
        guard fetch == nil else { return }
        lastFetch = now
        let device = device, connection = connection, id = UUID(); request = id
        fetch = Task { [weak self] in
            guard let self else { return }
            defer { if request == id { fetch = nil } }
            do {
                let data = try await loader(device, now)
                guard !Task.isCancelled, request == id, self.scope == scope, Settings.connectionID == connection else { return }
                snapshot = data; persistSnapshot(); reconcileSoon(); completion.receive(data)
            } catch {
                guard !Task.isCancelled, request == id, self.scope == scope, Settings.connectionID == connection else { return }
                // Keep the labelled last-sync snapshot and retry any failed scheduling.
                reconcileSoon()
            }
        }
    }
    /// Reuse a successfully scoped current-day response already fetched by a visible screen.
    func receive(_ data: ZoopAPI.StepsDay, scope: String?) {
        guard scope != nil, scope == self.scope, data.walking > 0 || data.total > 0 else { return }
        let now = clock()
        guard data.day == CutPlan.key(now, calendar: calendar()), data.walking >= 0 else { return }
        fetch?.cancel(); fetch = nil; request = UUID(); lastFetch = now
        snapshot = .init(day: data.day, steps: data.walking); persistSnapshot(); reconcileSoon(); completion.receive(snapshot)
    }
    private func persistSnapshot() {
        guard let scope else { return }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: "stepsReminder." + scope) }
        else { defaults.removeObject(forKey: "stepsReminder." + scope) }
    }
    private func reconcileSoon() {
        revision &+= 1
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while true { let current = revision; await reconcile(); if current == revision { worker = nil; return } }
        }
    }
    func settled() async { await fetch?.value; await worker?.value; await completion.settled() }
    private func reconcile() async {
        let now = clock(), calendar = calendar(), scope = scope, snapshot = snapshot
        let day = CutPlan.key(now, calendar: calendar)
        let target = CutTargets.steps(goal: goal, day: now, now: now, calendar: calendar)
        let permission = await center.authorization()
        let allowed = enabled && scope != nil && target != nil && (permission == .authorized || permission == .provisional)
        let known = snapshot?.day == day && (snapshot?.steps ?? -1) >= 0
        let remaining = known ? max(0, (target ?? 0) - (snapshot?.steps ?? 0)) : 0
        let id = Self.prefix + (scope ?? "") + "." + day
        let at = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: now)
        let withinCut = at.map { CutTargets.steps(goal: goal, day: $0, now: $0, calendar: calendar) != nil } ?? false
        let attempted = receipts[id].map { $0 <= now } ?? false
        let wanted = allowed && withinCut && known && remaining > 0 && (0..<1440).contains(minute) && at.map { $0 > now } == true && !attempted
        let pending = await center.pending()
        center.removePending(pending.filter { $0.identifier.hasPrefix(Self.prefix) && (!wanted || $0.identifier != id) }.map(\.identifier))
        let delivered = await center.delivered()
        center.removeDelivered(delivered.filter { $0.request.identifier.hasPrefix(Self.prefix) && ($0.request.identifier != id || !allowed || (known && remaining == 0)) }.map { $0.request.identifier })
        error = nil
        guard wanted, let at, let scope else { return }
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: at); components.timeZone = calendar.timeZone
        let body = "\(remaining.formatted()) steps left at your last sync."
        if let old = pending.first(where: { $0.identifier == id }), let trigger = old.trigger as? UNCalendarNotificationTrigger, trigger.dateComponents == components, old.content.body == body { return }
        let content = UNMutableNotificationContent()
        content.title = "Your steps goal"
        content.body = body; content.sound = .default; content.threadIdentifier = "snoop.steps-goal"
        content.userInfo = ["destination": "steps", "scope": scope, "day": day]
        do {
            try await center.add(.init(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            receipts[id] = at; receipts = receipts.filter { $0.value > now.addingTimeInterval(-3 * 86400) }
            if let data = try? JSONEncoder().encode(receipts) { defaults.set(data, forKey: "reminders.stepsReceipts") }
        } catch { self.error = "Couldn’t schedule your steps reminder. Try again." }
    }
}
