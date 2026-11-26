import Observation
import Foundation
import ZoopSync
import ZoopData
import UserNotifications

/// Wires the strap manager to the local queue and the uploader.
@MainActor
@Observable
final class AppModel {
    private(set) var accountErasureInProgress = AccountErasure.pending != nil
    private var erasingAccount = false
    private(set) var accountErasureError: String?
    private(set) var queued = 0
    private(set) var heldFrames = 0
    private(set) var processing: ZoopAPI.Processing?
    private(set) var processingError: String?
    private(set) var uploadStats = Uploader.Stats()
    private(set) var queueError: String?
    private(set) var isUploading = false
    /// Frames accepted by the most recent successful upload, for the status line.
    private(set) var lastBatchAccepted = 0

    private var accountCredential = Settings.credential
    var dataDevice: String {
        Settings.dataDevice(physicalSerial: strap.serial, credential: accountCredential)
    }

    let strap: StrapManager
    let ecg: ECGRecorder
    let battery = BatteryMonitor()
    let reminders = DailyReminderScheduler()
    let weeklyWeight = WeeklyWeightStore()
    let stepsReminder = StepGoalReminder()
    let offBody = OffBodyMonitor()
    @ObservationIgnored private var reminderSettingsObserver: NSObjectProtocol?
    @ObservationIgnored private var reminderConnection = Settings.connectionID
    let workouts = WorkoutNotifier()
    let activity = WorkoutStore()
    let sleep = SleepStore()
    let health = HealthCoordinator()
    let widgets = WidgetPublisher()
    let photo = ProfilePhotoStore()
    let sleepGoal: SleepGoalStore
    var analysisRevision = 0
    private(set) var analysisUpdating = false
    private static let analysisRefreshAttempts = 120
    private static let analysisRefreshDelay: Duration = .seconds(2)
    private var analysisRefresh: Task<Void, Never>?
    private let storage = FrameStorage()
    private var uploader: Uploader?
    private var storageReady = false
    private var startRequested = false
    private var analysisRequest = UUID()
    private var writer: FrameWriter?
    private var flushTimer: Timer?
    private var capturedSinceFlush = 0
    private var flushScheduled = false
    // Explicit, one-launch recovery after the owner of a pre-v2 backlog is confirmed.
    private var recoverLegacyOnNextBinding = ProcessInfo.processInfo.arguments.contains("-recoverLegacyFrames")

    static let flushInterval: TimeInterval = 60
    static let onboardedKey = "onboarded"

    var isOnboarded = UserDefaults.standard.bool(forKey: AppModel.onboardedKey) {
        didSet { UserDefaults.standard.set(isOnboarded, forKey: Self.onboardedKey) }
    }

    init(servicesEnabled: Bool = true) {
        let strap = StrapManager()
        self.strap = strap
        sleepGoal = SleepGoalStore(legacyScope: .init(device: Settings.dataDevice(physicalSerial: strap.serial, credential: Settings.credential), connection: Settings.connectionID))
        ecg = ECGRecorder(transport: strap)
        guard servicesEnabled else { return }
        weeklyWeight.onGoalChange = { [weak self] in self?.refreshStepsReminder() }
        health.onReminderChange = { [weak self] in
            guard let self else { return }
            self.refreshReminders(); self.widgets.weight(self)
        }
        ecg.onHistoryChanged = { [weak self] in self?.refreshReminders() }
        reminderSettingsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.reminderConnection != Settings.connectionID || self.accountCredential != Settings.credential else { return }
                self.reminderConnection = Settings.connectionID
                self.accountCredential = Settings.credential
                self.ecg.accountChanged()
                self.sleep.activate(self.dataDevice)
                self.activity.activate(self.dataDevice)
                self.health.activate(self.dataDevice)
                self.refreshReminders()
            }
        }

        strap.onECGFrame = { [weak self] bytes, at, uptime in self?.ecg.receive(bytes, at: at, uptime: uptime) }
        strap.onECGInvalidFrame = { [weak self] in self?.ecg.invalidFrame() }
        strap.onECGAvailability = { [weak self] in self?.ecg.connectionChanged() }
        ecg.connectionChanged()
        Task { await openStorage() }
        strap.onFrame = { [weak self] bytes, channel, saved in
            guard let self, !self.erasingAccount, !self.accountErasureInProgress, let writer = self.writer else {
                self?.strap.pauseHistoryForStorage()
                return
            }
            writer.enqueue(bytes, channel: channel, sourceID: self.strap.storageOwner) { [weak self] in
                saved()
                guard let self else { return }
                self.queued += 1
                self.capturedSinceFlush += 1
                if self.capturedSinceFlush >= Uploader.batchSize, !self.flushScheduled, !self.isUploading {
                    self.flushScheduled = true
                    Task { await self.flush(); self.flushScheduled = false }
                }
            }
        }
        strap.onBatteryDevice = { [weak self] id in self?.battery.activate(device: id) }
        strap.onSerial = { [weak self] serial in
            guard let self else { return }
            self.offBody.invalidate()
            self.workouts.activate(device: serial)
            self.health.activate(serial)
            self.ecg.connectionChanged()
            Task { await self.bindCurrentDevice() }
        }
        if !strap.serial.isEmpty { workouts.activate(device: strap.serial) }
        health.activate(dataDevice)
        strap.onBatteryLevel = { [weak self] percent, at, live, source in self?.battery.receive(percent: percent, at: at, live: live, source: source) }
        strap.onCharging = { [weak self] charging, at, live in self?.battery.receive(charging: charging, at: at, live: live) }
        strap.onPackInfo = { [weak self] info, at, live, cached in
            self?.battery.receivePack(percent: info.percent, identifier: info.identifier, present: info.present, at: at, live: live, cached: cached)
        }
        strap.onPackPresence = { [weak self] present, at, live in self?.battery.receivePackPresence(present, at: at, live: live) }
        strap.onWearEvent = { [weak self] code, at, live in self?.offBody.receive(code: code, at: at, live: live) }
        strap.onBatteryDisconnect = { [weak self] in self?.battery.disconnected(); self?.offBody.invalidate() }

        flushTimer = Timer.scheduledTimer(withTimeInterval: Self.flushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.flush() }
        }

    }

    func refreshReminders() {
        guard isOnboarded, let scope = health.reminderScope else { reminders.update(nil); weeklyWeight.activate(device: "", scope: nil); return }
        weeklyWeight.activate(device: health.reminderDevice, scope: scope)
        let ecgDays = Set(ecg.recordings.filter { $0.device == health.reminderDevice && $0.sampleCount > 0 }.map { DayKey.string($0.startedAt) })
        reminders.update(.init(scope: scope, weightEnabled: health.canRemind, weightDays: health.reminderWeightDays, ecgDays: ecgDays))
    }

    private func refreshStepsReminder() {
        stepsReminder.activate(goal: isOnboarded ? weeklyWeight.goal : nil, device: health.reminderDevice, scope: isOnboarded ? health.reminderScope : nil)
    }

    private func openStorage() async {
        do {
            let queue = try await storage.open()
            uploader = Uploader(queue: queue)
            writer = FrameWriter(save: { bytes, channel, at, source in
                try queue.enqueue(bytes, channel: channel, receivedAt: at, sourceID: source)
            }, onFailure: { [weak self] error in
                self?.queueError = "Storage paused: \(error.localizedDescription)"
                self?.strap.pauseHistoryForStorage()
            }, onRecovery: { [weak self] in
                self?.queueError = nil
                self?.strap.resumeHistoryAfterStorage()
            })
            storageReady = true
            if AccountErasure.pending != nil { await resumeAccountErasure(); return }
            await updateQueueCounts()
            await bindCurrentDevice()
            if Settings.isConfigured && (isOnboarded || startRequested) { strap.start() }
        } catch { queueError = "queue unavailable: \(error)" }
    }

    func startStrap() {
        startRequested = true
        if storageReady && !accountErasureInProgress && Settings.isConfigured { strap.start() }
    }

    private func bindCurrentDevice() async {
        guard storageReady, let source = strap.storageOwner, !strap.serial.isEmpty else { return }
        let recover = recoverLegacyOnNextBinding
        recoverLegacyOnNextBinding = false
        do {
            try await storage.bind(sourceID: source, deviceID: strap.serial, adoptLegacy: recover)
            if recover {
                queueError = nil
                await updateQueueCounts()
                Task { await self.flush() }
            }
        } catch { queueError = error.localizedDescription }
    }

    private func updateQueueCounts() async {
        guard let counts = try? await storage.counts() else { return }
        queued = counts.queued; heldFrames = counts.held
        if counts.unassigned > 0 { queueError = "\(counts.unassigned) older frames have no recorded device identity and are safely retained." }
    }

    /// Poll a small status response; reload complete projections only after analysis.
    func refreshAnalysis() {
        analysisRefresh?.cancel()
        sleep.dismissNotice(); activity.dismissNotice()
        analysisUpdating = true; analysisRevision += 1
        let request = UUID(); analysisRequest = request
        let device = dataDevice, connection = Settings.connectionID
        analysisRefresh = Task { [weak self] in
            defer {
                if let self, self.analysisRequest == request { self.analysisUpdating = false }
            }
            guard let self else { return }
            do {
                let ready = try await RefreshPoller.wait(attempts: Self.analysisRefreshAttempts, delay: Self.analysisRefreshDelay) {
                    guard self.dataDevice == device, Settings.connectionID == connection, self.analysisRequest == request else { throw CancellationError() }
                    do { return try await ZoopAPI.processing(deviceId: device).pendingAnalysis == 0 }
                    catch is CancellationError { throw CancellationError() }
                    catch { self.processingError = error.localizedDescription; return false }
                }
                guard !Task.isCancelled, self.analysisRequest == request, self.dataDevice == device, Settings.connectionID == connection else { return }
                guard ready else { self.processingError = "Analysis is still refreshing. Try again shortly."; return }
                await ZoopAPI.invalidateReads()
                async let nights: () = self.sleep.reload(device: device)
                async let sessions: () = self.activity.reload(device: device)
                _ = try await (nights, sessions)
                guard !Task.isCancelled, self.analysisRequest == request else { return }
                self.processingError = nil; self.analysisRevision += 1
                self.stepsReminder.refresh(force: true)
                self.health.checkSoon()
            } catch is CancellationError { }
            catch { if self.analysisRequest == request { self.processingError = error.localizedDescription } }

        }
    }

    func flush() async {
        guard !accountErasureInProgress && !erasingAccount else { return }
        writer?.retry()
        guard let uploader, let baseURL = Settings.serverURL, Settings.isConfigured, !strap.serial.isEmpty, !isUploading else { return }
        let device = strap.serial, connection = Settings.connectionID
        let token = Settings.ingestToken, model = strap.model, firmware = strap.firmware
        await bindCurrentDevice()
        guard !isUploading, strap.serial == device, Settings.connectionID == connection else { return }
        capturedSinceFlush = 0
        isUploading = true
        defer { isUploading = false }
        let before = uploadStats.accepted
        let previousDuplicates = uploadStats.duplicates
        let stats = await uploader.flush(deviceId: device, model: model, firmware: firmware, baseURL: baseURL, token: token)
        guard strap.serial == device, Settings.connectionID == connection else { return }
        uploadStats = stats
        lastBatchAccepted = uploadStats.accepted - before
        if lastBatchAccepted > 0 || uploadStats.duplicates > previousDuplicates { workouts.checkSoon(); stepsReminder.refresh() }
        await updateQueueCounts()
        do {
            let status = try await ZoopAPI.processing(deviceId: device)
            guard strap.serial == device, Settings.connectionID == connection else { return }
            processing = status
            processingError = nil
        } catch { if strap.serial == device, Settings.connectionID == connection { processingError = error.localizedDescription } }
        widgets.refresh(self)
        health.activate(strap.serial)
        health.checkSoon()
    }

    func deleteAccount(password: String) async throws {
        guard let credential = Settings.credential, !accountErasureInProgress && !erasingAccount else { throw ServerSignIn.Failure.changed }
        let identity = try await ServerSignIn.identity(credential)
        guard Settings.credential == credential else { throw ServerSignIn.Failure.changed }
        erasingAccount = true; strap.stop()
        do {
            try await writer?.stop()
            let receipt = AccountErasure(account: identity.account.id, devices: identity.devices,
                scopes: identity.devices.map { Settings.healthScope(device: $0, credential: credential) },
                photoKeys: identity.devices.map { ProfilePhotoStore.Scope(device: $0, connection: Settings.connectionID).diskKey })
            try await ServerSignIn.deleteAccount(credential, password: password)
            try receipt.persist()
        } catch {
            erasingAccount = false; writer?.retry(); startStrap()
            throw error
        }
        await resumeAccountErasure()
    }

    func resumeAccountErasure() async {
        guard let receipt = AccountErasure.pending else { return }
        accountErasureInProgress = true; accountErasureError = nil
        strap.stop(); analysisRefresh?.cancel()
        do {
            try await writer?.stop()
            try Settings.clear()
            reminders.update(nil); weeklyWeight.activate(device: "", scope: nil)
            stepsReminder.activate(goal: nil, device: "", scope: nil)
            workouts.activate(device: "")
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            try await health.eraseLocal(scopes: receipt.scopes)
            try await ecg.eraseLocal(devices: receipt.devices)
            try await photo.eraseLocal(keys: receipt.photoKeys)
            try await storage.eraseDevices(receipt.devices)
            for scope in receipt.scopes {
                UserDefaults.standard.removeObject(forKey: "weeklyWeight." + scope)
                UserDefaults.standard.removeObject(forKey: "stepsReminder." + scope)
            }
            UserDefaults.standard.removeObject(forKey: "health.lastDevice")
            await updateQueueCounts()
            AccountErasure.finish(); accountErasureInProgress = false; erasingAccount = false
            // The stopped writer is replaced before the next connection starts.
            await openStorage()
        } catch { accountErasureError = "Your server account is deleted. Unlock this iPhone and retry to finish removing its local data." }
    }

    func retryHeldFrames() async {
        do { try await storage.retryHeld(); await flush() }
        catch { queueError = error.localizedDescription }
    }

    /// Why an upload cannot start right now, or nil when it can.
    var uploadBlocker: String? {
        if !Settings.isConfigured { return "Set the server URL and token in Settings." }
        if strap.serial.isEmpty { return "Waiting for the strap's serial number." }
        return nil
    }
}
