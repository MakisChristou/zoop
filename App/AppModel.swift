import Combine
import Foundation
import SwiftUI

/// Wires the strap manager to the local queue and the uploader.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var queued = 0
    @Published private(set) var uploadStats = Uploader.Stats()
    @Published private(set) var queueError: String?
    @Published private(set) var isUploading = false
    /// Frames accepted by the most recent successful upload, for the status line.
    @Published private(set) var lastBatchAccepted = 0

    let strap = StrapManager()
    let battery = BatteryMonitor()
    private let queue: FrameQueue?
    private let uploader: Uploader?
    private var flushTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    static let flushInterval: TimeInterval = 60
    static let onboardedKey = "onboarded"

    var isOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: Self.onboardedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.onboardedKey); objectWillChange.send() }
    }

    init() {
        do {
            let queue = try FrameQueue(path: try FrameQueue.defaultPath())
            self.queue = queue
            uploader = Uploader(queue: queue)
            queued = (try? queue.count()) ?? 0
        } catch {
            queue = nil
            uploader = nil
            queueError = "queue unavailable: \(error)"
        }

        strap.onFrame = { [weak self] bytes, channel in
            Task { @MainActor in self?.enqueue(bytes, channel: channel) }
        }
        strap.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        battery.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        strap.onBatteryDevice = { [weak self] id in self?.battery.activate(device: id) }
        strap.onBatteryLevel = { [weak self] percent, at, live, source in self?.battery.receive(percent: percent, at: at, live: live, source: source) }
        strap.onCharging = { [weak self] charging, at, live in self?.battery.receive(charging: charging, at: at, live: live) }
        strap.onPackInfo = { [weak self] info, at, live, cached in
            self?.battery.receivePack(percent: info.percent, identifier: info.identifier, present: info.present, at: at, live: live, cached: cached)
        }
        strap.onPackPresence = { [weak self] present, at, live in self?.battery.receivePackPresence(present, at: at, live: live) }
        strap.onBatteryDisconnect = { [weak self] in self?.battery.disconnected() }

        flushTimer = Timer.scheduledTimer(withTimeInterval: Self.flushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.flush() }
        }

        if isOnboarded { strap.start() }
    }

    private func enqueue(_ bytes: [UInt8], channel: Int) {
        guard let queue else { return }
        do {
            try queue.enqueue(bytes, channel: channel)
            queued += 1
            if queued >= Uploader.batchSize { Task { await flush() } }
        } catch {
            queueError = "enqueue failed: \(error)"
        }
    }

    func flush() async {
        guard let uploader, let queue, Settings.isConfigured, !strap.serial.isEmpty, !isUploading else { return }
        isUploading = true
        defer { isUploading = false }
        let before = uploadStats.accepted
        uploadStats = await uploader.flush(deviceId: strap.serial, model: strap.model, firmware: strap.firmware)
        lastBatchAccepted = uploadStats.accepted - before
        queued = (try? queue.count()) ?? queued
    }

    /// Why an upload cannot start right now, or nil when it can.
    var uploadBlocker: String? {
        if !Settings.isConfigured { return "Set the server URL and token in Settings." }
        if strap.serial.isEmpty { return "Waiting for the strap's serial number." }
        return nil
    }
}
