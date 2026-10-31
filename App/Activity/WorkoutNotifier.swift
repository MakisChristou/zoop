import Foundation
import OSLog
import UserNotifications

/// Tells the user about sessions the server has detected. Detection happens on the
/// server, so after each successful upload the sessions are fetched and any id not
/// seen before gets one local notification. The seen set persists per strap, and the
/// first run on a strap seeds it silently so an old history does not arrive as a
/// burst of alerts. Taps are routed by `BatteryMonitor`, the notification delegate.
@MainActor
final class WorkoutNotifier: ObservableObject {
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var notificationError: String?

    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter
    private let log = Logger(subsystem: "snoop", category: "workouts")
    private var device: String?
    private var seen: Set<Int64> = []
    private var pending: Task<Void, Never>?

    /// Uploads arrive every minute; the server analyses every few minutes. One check
    /// per interval is plenty.
    static let minimumInterval: TimeInterval = 180
    /// Uploads keep landing while the strap offloads; wait for the server to catch up.
    static let settleDelay: TimeInterval = 20
    static let maximumAlertsPerCheck = 3

    init(defaults: UserDefaults = .standard, center: UNUserNotificationCenter = .current()) {
        self.defaults = defaults
        self.center = center
    }

    func activate(device: String) {
        guard device != self.device else { return }
        pending?.cancel()
        self.device = device
        seen = Set((defaults.array(forKey: key(device)) as? [Int64]) ?? [])
        lastCheckedAt = nil
    }

    /// Schedules a check shortly after an upload, at most once per interval.
    func checkSoon() {
        guard device != nil else { return }
        if let last = lastCheckedAt, Date().timeIntervalSince(last) < Self.minimumInterval { return }
        guard pending == nil else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.settleDelay))
            guard !Task.isCancelled else { return }
            await self?.check()
            self?.pending = nil
        }
    }

    func check() async {
        guard let device, Settings.isConfigured else { return }
        lastCheckedAt = Date()
        guard let workouts = try? await SnoopAPI.workouts(deviceId: device, limit: 20) else { return }
        let ids = Set(workouts.map(\.id))
        let firstRun = defaults.array(forKey: key(device)) == nil
        if firstRun {
            seen = ids
            save()
            return
        }
        let fresh = workouts.filter { !seen.contains($0.id) }.sorted { $0.startTs < $1.startTs }
        for workout in fresh.suffix(Self.maximumAlertsPerCheck) {
            await notify(workout)
        }
        seen.formUnion(ids)
        save()
    }

    private func notify(_ workout: SnoopAPI.Workout) async {
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
            try await center.add(UNNotificationRequest(identifier: "snoop.workout.\(device ?? "strap").\(workout.id)", content: content, trigger: nil))
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

    private func key(_ device: String) -> String { "workouts.\(device).seen" }
}
