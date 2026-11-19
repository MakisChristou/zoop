import Observation
import Foundation
import OSLog
import UserNotifications

/// Tells the user about sessions the server has detected. Detection happens on the
/// server on its own schedule, so the app checks the session list shortly after each
/// accepted upload, again one analysis interval later in case the server had not
/// finished, and whenever it returns to the foreground. Sessions are recognised by
/// a stable server identity, including edits and recalculations; the seen set
/// persists per strap serial, and the first run on a strap seeds it silently so an
/// old history does not arrive as a burst of alerts. Taps are routed by
/// `BatteryMonitor`, the notification delegate.
@MainActor
@Observable
final class WorkoutNotifier {
    private(set) var lastCheckedAt: Date?
    private(set) var notificationError: String?

    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter
    private let log = Logger(subsystem: "snoop", category: "workouts")
    private var device: String?
    private var seen: Set<Int64> = []
    private var pending: Task<Void, Never>?
    private var followUp: Task<Void, Never>?

    /// Uploads keep landing while the strap offloads; wait for the server to catch up.
    static let settleDelay: TimeInterval = 20
    /// Back-to-back uploads share one check.
    static let minimumInterval: TimeInterval = 120
    /// The server's analysis cadence; the follow-up check lands just after it.
    static let analysisInterval: TimeInterval = 15 * 60
    static let maximumAlertsPerCheck = 3

    init(defaults: UserDefaults = .standard, center: UNUserNotificationCenter = .current()) {
        self.defaults = defaults
        self.center = center
    }

    /// `device` is the strap serial, the id every upload and read uses.
    func activate(device: String) {
        guard device != self.device else { return }
        pending?.cancel()
        followUp?.cancel()
        self.device = device
        seen = Set((defaults.array(forKey: key(device)) as? [NSNumber])?.map(\.int64Value) ?? [])
        lastCheckedAt = nil
    }

    /// Schedules a check after the settle delay, throttled unless `force`, and a
    /// follow-up one analysis interval later.
    func checkSoon(force: Bool = false) {
        guard device != nil else { return }
        if !force, let last = lastCheckedAt, Date().timeIntervalSince(last) < Self.minimumInterval { return }
        if pending == nil || force {
            pending?.cancel()
            pending = Task { [weak self] in
                try? await Task.sleep(for: .seconds(force ? 1 : Self.settleDelay))
                guard !Task.isCancelled else { return }
                await self?.check()
                self?.pending = nil
            }
        }
        followUp?.cancel()
        followUp = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.analysisInterval + Self.settleDelay))
            guard !Task.isCancelled else { return }
            await self?.check()
            self?.followUp = nil
        }
    }

    func check() async {
        guard let device, Settings.isConfigured else { return }
        lastCheckedAt = Date()
        guard let workouts = try? await ZoopAPI.workouts(deviceId: device, limit: 20) else { return }
        let keys = Set(workouts.map(Self.key))
        let firstRun = defaults.array(forKey: key(device)) == nil
        if firstRun {
            seen = keys
            save()
            return
        }
        let fresh = workouts.filter { !seen.contains(Self.key($0)) && $0.notificationEligible == true && $0.endTs > Date().addingTimeInterval(-24 * 60 * 60) }.sorted { $0.startTs < $1.startTs }
        for workout in fresh.suffix(Self.maximumAlertsPerCheck) {
            await notify(workout)
        }
        seen.formUnion(keys)
        save()
    }

    /// Stable identities keep corrections and recalculations silent.
    /// The new defaults key seeds old installs silently on their first check.
    static func key(_ workout: ZoopAPI.Workout) -> Int64 { workout.id }

    private func notify(_ workout: ZoopAPI.Workout) async {
        let kind = ActivityKind.named(workout.kind)
        let content = UNMutableNotificationContent()
        content.title = kind == .activity ? "Activity detected" : "\(kind.name) detected"
        var parts = ["\(workout.durationS / 60) min"]
        if let load = workout.load { parts.append("load \(load.formatted(.number.precision(.fractionLength(1))))") }
        if let kcal = workout.kcal { parts.append("\(Int(kcal.rounded())) kcal") }
        content.body = kind == .activity ? parts.joined(separator: " · ") + " · tap to label it" : parts.joined(separator: " · ")
        content.sound = .default
        content.threadIdentifier = "snoop.workout"
        content.userInfo = ["destination": "workout", "id": workout.id]
        do {
            try await center.add(UNNotificationRequest(identifier: "snoop.workout.\(device ?? "strap").\(Self.key(workout))", content: content, trigger: nil))
            notificationError = nil
        } catch {
            notificationError = "A session alert could not be delivered. Check notification settings."
            log.error("notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        guard let device else { return }
        defaults.set(Array(seen), forKey: key(device))
    }

    private func key(_ device: String) -> String { "workouts.\(device).seen.ids" }
}
