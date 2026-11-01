import Combine
import Foundation
import SwiftUI
import SnoopSync

/// Wires the strap manager to the local queue and the uploader.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var queued = 0
    @Published private(set) var heldFrames = 0
    @Published private(set) var processing: SnoopAPI.Processing?
    @Published private(set) var processingError: String?
    @Published private(set) var uploadStats = Uploader.Stats()
    @Published private(set) var queueError: String?
    @Published private(set) var isUploading = false
    /// Frames accepted by the most recent successful upload, for the status line.
    @Published private(set) var lastBatchAccepted = 0

    let strap = StrapManager()
    let battery = BatteryMonitor()
    let workouts = WorkoutNotifier()
    let activity = WorkoutStore()
    let sleep = SleepStore()
    @Published var analysisRevision = 0
    @Published private(set) var analysisUpdating = false
    private static let analysisRefreshAttempts = 120
    private static let analysisRefreshDelay: Duration = .seconds(2)
    private var analysisRefresh: Task<Void, Never>?
    private let queue: FrameQueue?
    private let uploader: Uploader?
    private var writer: FrameWriter?
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

        if let queue {
            writer = FrameWriter(save: { bytes, channel, at in
                try queue.enqueue(bytes, channel: channel, receivedAt: at)
            }, onFailure: { [weak self] error in
                self?.queueError = "Storage paused: \(error.localizedDescription)"
                self?.strap.pauseHistoryForStorage()
            }, onRecovery: { [weak self] in
                self?.queueError = nil
                self?.strap.resumeHistoryAfterStorage()
            })
        }
        strap.onFrame = { [weak self] bytes, channel, saved in
            guard let self, let writer = self.writer else {
                self?.strap.pauseHistoryForStorage()
                return
            }
            writer.enqueue(bytes, channel: channel) { [weak self] in
                saved()
                guard let self else { return }
                self.queued += 1
                if self.queued - self.heldFrames >= Uploader.batchSize { Task { await self.flush() } }
            }
        }
        strap.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        battery.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        sleep.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        activity.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        workouts.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        strap.onBatteryDevice = { [weak self] id in self?.battery.activate(device: id) }
        // Sessions are keyed by the strap serial, the id every upload and read uses.
        strap.$serial
            .filter { !$0.isEmpty }
            .removeDuplicates()
            .sink { [weak self] serial in self?.workouts.activate(device: serial) }
            .store(in: &cancellables)
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

    /// Refresh projections after reset without creating a detection notification.
    func refreshAnalysis() {
        analysisRefresh?.cancel()
        sleep.dismissNotice(); activity.dismissNotice()
        analysisUpdating = true
        analysisRevision += 1
        let device = strap.serial
        analysisRefresh = Task { [weak self] in
            for _ in 0..<Self.analysisRefreshAttempts {
                guard let self, !Task.isCancelled, self.strap.serial == device else { return }
                try? await self.sleep.reload(device: device)
                try? await self.activity.reload(device: device)
                if let status = try? await SnoopAPI.processing(deviceId: device), status.pendingAnalysis == 0 {
                    self.analysisUpdating = false
                    self.analysisRevision += 1
                    return
                }
                do { try await Task.sleep(for: Self.analysisRefreshDelay) } catch { return }
            }
        }
    }

    func flush() async {
        writer?.retry()
        guard let uploader, let queue, let baseURL = Settings.serverURL, Settings.isConfigured, !strap.serial.isEmpty, !isUploading else { return }
        isUploading = true
        defer { isUploading = false }
        let before = uploadStats.accepted
        let previousDuplicates = uploadStats.duplicates
        uploadStats = await uploader.flush(deviceId: strap.serial, model: strap.model, firmware: strap.firmware, baseURL: baseURL, token: Settings.ingestToken)
        lastBatchAccepted = uploadStats.accepted - before
        if lastBatchAccepted > 0 || uploadStats.duplicates > previousDuplicates { workouts.checkSoon() }
        queued = (try? queue.count()) ?? queued
        heldFrames = (try? queue.heldCount()) ?? heldFrames
        do {
            processing = try await SnoopAPI.processing(deviceId: strap.serial)
            processingError = nil
        } catch { processingError = error.localizedDescription }
    }

    func retryHeldFrames() async {
        do { try queue?.retryHeld(); await flush() }
        catch { queueError = error.localizedDescription }
    }

    /// Why an upload cannot start right now, or nil when it can.
    var uploadBlocker: String? {
        if !Settings.isConfigured { return "Set the server URL and token in Settings." }
        if strap.serial.isEmpty { return "Waiting for the strap's serial number." }
        return nil
    }
}
