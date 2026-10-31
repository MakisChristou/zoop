import Combine
import Foundation
import OSLog
import SnoopBattery
import UserNotifications

/// Keeps battery observations and notification deduplication across app launches.
@MainActor
final class BatteryMonitor: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var state = BatteryState()
    @Published private(set) var pack = PackBatteryState()
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var notificationError: String?
    @Published var openBattery = false

    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter
    private var deviceKey: String?
    private var policy = BatteryAlertPolicy()
    private var packPolicy = BatteryAlertPolicy()
    private var lastPackReminderAt: Date?
    private var liveLevelAt: Date?
    private var pending: Task<Void, Never>?
    private var pendingPackEvent: Date?
    private let log = Logger(subsystem: "snoop", category: "battery")

    init(defaults: UserDefaults = .standard, center: UNUserNotificationCenter = .current()) {
        self.defaults = defaults
        self.center = center
        super.init()
        center.delegate = self
        if let key = defaults.string(forKey: "battery.lastDevice") { activate(device: key) }
    }

    func activate(device: String) {
        guard device != deviceKey else { return }
        pending?.cancel()
        deviceKey = device
        defaults.set(device, forKey: "battery.lastDevice")
        state = restore(BatteryState.self, suffix: "state") ?? BatteryState()
        state.invalidateCharging(at: Date())
        policy = restore(BatteryAlertPolicy.self, suffix: "policy") ?? BatteryAlertPolicy()
        pack = restore(PackBatteryState.self, suffix: "packState") ?? PackBatteryState()
        pack.disconnect(at: Date())
        packPolicy = restore(BatteryAlertPolicy.self, suffix: "packPolicy") ?? BatteryAlertPolicy()
        lastPackReminderAt = restore(Date.self, suffix: "packReminder")
        liveLevelAt = nil
        pendingPackEvent = nil
    }

    func disconnected() {
        pending?.cancel()
        liveLevelAt = nil
        pendingPackEvent = nil
        state.invalidateCharging(at: Date())
        pack.disconnect(at: Date())
        save(pack, suffix: "packState")
        save(state, suffix: "state")
    }

    func receive(percent: Double, at date: Date, live: Bool, source: BatteryReadingSource = .event) {
        let wasCharging = state.chargingStatus(at: Date())
        guard state.receive(percent: percent, at: date, now: Date(), live: live, source: source) else { return }
        if state.chargingEvidence == .risingLevel, wasCharging != state.chargingStatus(at: Date()) {
            log.info("charging trend: \(self.state.charging == true), level: \(percent)")
        }
        if live, wasCharging != true, state.chargingStatus(at: Date()) == true { chargingResumed() }
        if live { liveLevelAt = date }
        save(state, suffix: "state")
        evaluateSoon()
    }

    func receive(charging: Bool, at date: Date, live: Bool) {
        guard state.receive(charging: charging, at: date, now: Date()) else { return }
        save(state, suffix: "state")
        // Old offload events must never produce reminders about past charge sessions.
        if live, Date().timeIntervalSince(date) <= BatteryState.freshness {
            if charging {
                chargingResumed()
            } else {
                pendingPackEvent = date
            }
        }
        evaluateSoon()
    }

    private func chargingResumed() {
        pendingPackEvent = nil
        center.removeDeliveredNotifications(withIdentifiers: [notificationID("pack"), notificationID("low")])
    }

    func receivePack(percent: Double?, identifier: [UInt8], present: Bool, at date: Date, live: Bool, cached: Bool) {
        guard present else {
            if !cached { receivePackPresence(false, at: date, live: live) }
            return
        }
        guard let percent else { return }
        let previousID = pack.identifier
        guard pack.receive(percent: percent, identifier: identifier, at: date, now: Date(), live: live, cached: cached) else { return }
        if previousID != pack.identifier { packPolicy = BatteryAlertPolicy() }
        save(pack, suffix: "packState")
        save(packPolicy, suffix: "packPolicy")
        evaluateSoon()
    }

    func receivePackPresence(_ present: Bool, at date: Date, live: Bool) {
        guard pack.receivePresence(present, at: date, now: Date(), live: live) else { return }
        if !present {
            // Removal is definitive even when CHARGING_OFF was missed.
            state.receive(charging: false, at: date, now: Date())
            save(state, suffix: "state")
        }
        save(pack, suffix: "packState")
    }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    func requestNotificationsIfNeeded() async {
        await refreshAuthorization()
        guard authorization == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
            notificationError = nil
            evaluateSoon()
        } catch {
            notificationError = "Notifications could not be enabled. Try again in Settings."
        }
    }

    private func evaluateSoon() {
        pending?.cancel()
        pending = Task { [weak self] in
            // Coalesce a battery reading with adjacent charging events before deciding.
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            await self?.evaluate()
        }
    }

    private func evaluate() async {
        await refreshAuthorization()
        guard !Task.isCancelled,
              authorization == .authorized || authorization == .provisional else { return }
        let key = deviceKey
        var next = policy
        let alert = next.evaluate(state, now: Date(), live: liveLevelAt == state.levelAt && liveLevelAt != nil)
        if let alert {
            let title: String
            let body: String
            let kind: String
            switch alert {
            case .low(let threshold):
                title = threshold <= 5 ? "Charge your WHOOP now" : "Time to charge your WHOOP"
                body = "Battery is at \(Int((state.percent ?? 0).rounded(.down)))%. Slide on the battery pack to keep recording."
                kind = "low"
            case .charged:
                title = "WHOOP is fully charged"
                body = "Your strap is at 100%. Remove the battery pack and recharge it for next time."
                kind = "full"
            }
            guard await notify(title: title, body: body, kind: kind), key == deviceKey else { return }
            if alert == .charged {
                center.removeDeliveredNotifications(withIdentifiers: [notificationID("low")])
            }
        }
        guard key == deviceKey else { return }
        policy = next
        save(policy, suffix: "policy")
        var nextPack = packPolicy
        let packID = pack.identifier
        let packAlert = nextPack.evaluate(pack.battery, now: Date(), live: pack.isLive(at: Date()))
        if let packAlert {
            let title: String
            let body: String
            switch packAlert {
            case .low:
                title = "Charge the battery pack"
                body = "The pack is at \(Int((pack.percent ?? 0).rounded(.down)))%. Plug it into USB-C."
            case .charged:
                title = "Battery pack is fully charged"
                body = "The pack is ready for your next WHOOP charge."
            }
            guard await notify(title: title, body: body, kind: "pack"), key == deviceKey, packID == pack.identifier else { return }
            pendingPackEvent = nil
        }
        guard key == deviceKey, packID == pack.identifier else { return }
        packPolicy = nextPack
        save(packPolicy, suffix: "packPolicy")
        if let event = pendingPackEvent, !policy.fullAlerted,
           pack.percent == nil,
           Date().timeIntervalSince(event) <= BatteryState.freshness,
           lastPackReminderAt.map({ event.timeIntervalSince($0) > 3600 }) ?? true {
            if await notify(title: "Recharge the battery pack", body: "Plug the pack into USB-C so it is ready for your next WHOOP charge.", kind: "pack"), key == deviceKey {
                lastPackReminderAt = event
                save(event, suffix: "packReminder")
                pendingPackEvent = nil
            }
        }
    }

    private func notify(title: String, body: String, kind: String) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "snoop.battery"
        content.userInfo = ["destination": "battery"]
        do {
            try await center.add(UNNotificationRequest(identifier: notificationID(kind), content: content, trigger: nil))
            notificationError = nil
            return true
        } catch {
            notificationError = "A battery alert could not be delivered. Check notification settings."
            return false
        }
    }

    private func notificationID(_ kind: String) -> String { "snoop.battery.\(deviceKey ?? "strap").\(kind)" }

    private func save<T: Encodable>(_ value: T, suffix: String) {
        guard let deviceKey, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: "battery.\(deviceKey).\(suffix)")
    }

    private func restore<T: Decodable>(_ type: T.Type, suffix: String) -> T? {
        guard let deviceKey, let data = defaults.data(forKey: "battery.\(deviceKey).\(suffix)") else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if response.notification.request.content.userInfo["destination"] as? String == "battery" { openBattery = true }
            completionHandler()
        }
    }
}
