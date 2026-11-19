import Foundation
import Observation
import ZoopData
import UserNotifications

/// Serial reconciliation: an older settings pass cannot leave requests behind after
/// a newer completion/scope change. Persisted receipts represent attempts, not delivery.
@MainActor @Observable final class DailyReminderScheduler {
    struct Input: Equatable {
        let scope: String
        let weightEnabled: Bool
        let weightDays: Set<String>
        let ecgDays: Set<String>
    }
    var weightMinute: Int { didSet { defaults.set(weightMinute, forKey: "reminders.weightMinute"); refresh() } }
    var ecgMinute: Int { didSet { defaults.set(ecgMinute, forKey: "reminders.ecgMinute"); refresh() } }
    var ecgEnabled: Bool { didSet { defaults.set(ecgEnabled, forKey: "reminders.ecgEnabled"); refresh() } }
    private(set) var error: String?
    private(set) var pendingCount = 0
    @ObservationIgnored private let center: ReminderNotificationClient
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: () -> Calendar
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var receipts: [String: Date]
    @ObservationIgnored private var input: Input?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var worker: Task<Void, Never>?

    init(center: ReminderNotificationClient = .live, defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init, calendar: @escaping () -> Calendar = { .current }) {
        self.center = center; self.defaults = defaults; self.clock = clock; self.calendar = calendar
        weightMinute = defaults.object(forKey: "reminders.weightMinute") as? Int ?? 9 * 60
        ecgMinute = defaults.object(forKey: "reminders.ecgMinute") as? Int ?? 20 * 60
        ecgEnabled = defaults.bool(forKey: "reminders.ecgEnabled")
        receipts = defaults.data(forKey: "reminders.receipts").flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
    }
    func update(_ next: Input?) { input = next; refresh() }
    func refresh() {
        revision &+= 1
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while true {
                let current = self.revision
                await self.reconcile()
                if current == self.revision { self.worker = nil; return }
            }
        }
    }
    /// Useful for verification without triggering an actual notification.
    func settled() async { await worker?.value }
    private func reconcile() async {
        let input = input, weightMinute = weightMinute, ecgMinute = ecgMinute, ecgEnabled = ecgEnabled
        let now = clock(), calendar = calendar()
        let permission = await center.authorization()
        var desired: [DailyReminderPlan.Entry] = []
        if let input, permission == .authorized || permission == .provisional {
            if input.weightEnabled {
                desired += DailyReminderPlan.entries(scope: input.scope, kind: "weight", minute: weightMinute, completedDays: input.weightDays, attempted: receipts, now: now, calendar: calendar)
            }
            if ecgEnabled {
                desired += DailyReminderPlan.entries(scope: input.scope, kind: "ecg", minute: ecgMinute, completedDays: input.ecgDays, attempted: receipts, now: now, calendar: calendar)
            }
        }
        let pending = await center.pending()
        let ids = Set(desired.map(\.id))
        // Migrate the old wake-based weight requests without touching battery/workout alerts.
        let obsolete = pending.filter { ($0.identifier.hasPrefix("snoop.daily.") && !ids.contains($0.identifier)) || $0.identifier.hasPrefix("snoop.weight.") }.map(\.identifier)
        center.removePending(obsolete)
        if let input {
            let delivered = await center.delivered()
            let completed = delivered.filter { note in
                let info = note.request.content.userInfo
                guard info["scope"] as? String == input.scope, let day = info["day"] as? String else { return false }
                return info["destination"] as? String == "weight" ? input.weightDays.contains(day) : info["destination"] as? String == "ecg" && input.ecgDays.contains(day)
            }.map { $0.request.identifier }
            center.removeDelivered(completed)
        }
        error = nil
        for entry in desired {
            if let existing = pending.first(where: { $0.identifier == entry.id }),
               let trigger = existing.trigger as? UNCalendarNotificationTrigger,
               trigger.nextTriggerDate().map({ abs($0.timeIntervalSince(entry.date)) < 1 }) == true { receipts[entry.id] = entry.date; continue }
            let content = UNMutableNotificationContent()
            content.title = entry.kind == "weight" ? "Morning check-in" : "Time for your ECG"
            content.body = entry.kind == "weight" ? "Take a moment to log your weight." : "Settle in for a quick recording."
            content.sound = .default; content.threadIdentifier = "snoop.checkins"
            content.userInfo = ["destination": entry.kind, "scope": input?.scope ?? "", "day": entry.day]
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: entry.date)
            components.timeZone = calendar.timeZone
            do {
                try await center.add(.init(identifier: entry.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
                receipts[entry.id] = entry.date
                // Save each accepted request, so a partial scheduling pass can recover.
                persistReceipts(now: now)
            } catch { self.error = "Couldn’t schedule reminders. Try again." }
        }
        pendingCount = await center.pending().filter { $0.identifier.hasPrefix("snoop.daily.") }.count
        persistReceipts(now: now)
    }
    private func persistReceipts(now: Date) {
        receipts = receipts.filter { $0.value > now.addingTimeInterval(-3 * 86400) }
        if let data = try? JSONEncoder().encode(receipts) { defaults.set(data, forKey: "reminders.receipts") }
    }
}
