import Foundation
import Observation
import OSLog
import SnoopBattery
import UserNotifications

/// Fresh live wear events schedule one reminder per removal episode.
@MainActor @Observable final class OffBodyMonitor {
    static let available = true
    private static let wornCode: UInt8 = 9
    private static let removedCode: UInt8 = 10
    private static let prefix = "snoop.offbody."
    var enabled: Bool { didSet { defaults.set(enabled, forKey: "reminders.offBody"); if !enabled { invalidate() } } }
    private(set) var removedAt: Date?
    private var policy = OffBodyPolicy()
    private let center: ReminderNotificationClient
    private let featureEnabled: Bool
    private let clock: () -> Date
    private var activeID: String?
    private let defaults: UserDefaults
    private var pending: Task<Void, Never>?
    private var generation = 0
    private let log = Logger(subsystem: "snoop", category: "wear")
    init(defaults: UserDefaults = .standard, center: ReminderNotificationClient = .live, featureEnabled: Bool = OffBodyMonitor.available, clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults; self.center = center; self.featureEnabled = featureEnabled; self.clock = clock
        enabled = defaults.object(forKey: "reminders.offBody") as? Bool ?? true
        // An old process cannot establish continuity. Leave any new episode alone.
        Task { [weak self] in
            let old = await center.pending()
            guard let self else { return }
            center.removePending(old.filter { ($0.identifier == "snoop.offbody" || $0.identifier.hasPrefix(Self.prefix)) && $0.identifier != self.activeID }.map(\.identifier))
        }
    }
    func receive(code: UInt8, at: Date, live: Bool) {
        guard code == Self.wornCode || code == Self.removedCode else { return }
        // Diagnostics record the code and event freshness only, never a health inference.
        if live { log.info("wear event: code=\(code), age=\(Date().timeIntervalSince(at))s") }
        guard featureEnabled, enabled, policy.receive(worn: code == Self.wornCode, at: at, now: clock(), live: live) else { return }
        let before = removedAt; removedAt = policy.removedAt
        guard before != removedAt else { return }
        generation &+= 1; let request = generation
        pending?.cancel()
        if let activeID { center.removePending([activeID]); center.removeDelivered([activeID]) }
        activeID = nil
        if removedAt == nil { return }
        guard let deadline = policy.deadline else { return }
        let id = Self.prefix + UUID().uuidString; activeID = id
        pending = Task {
            let permission = await center.authorization()
            guard !Task.isCancelled, generation == request, permission == .authorized || permission == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "WHOOP is off-body"
            content.body = "It’s been 10 minutes. Put it back on to keep recording."
            content.sound = .default; content.threadIdentifier = "snoop.device"; content.userInfo = ["destination": "battery"]
            do {
                try await center.add(.init(identifier: id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSince(clock())), repeats: false)))
                if Task.isCancelled || generation != request { center.removePending([id]) }
            } catch { log.error("Could not schedule off-body reminder") }
        }
    }
    func invalidate() {
        generation &+= 1; pending?.cancel(); policy.invalidate(); removedAt = nil
        if let activeID { center.removePending([activeID]); center.removeDelivered([activeID]) }
        activeID = nil
    }
    func settled() async { await pending?.value }
}
