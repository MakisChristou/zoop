import Observation
import SnoopData
import CryptoKit
import Foundation
import HealthKit
import SnoopHealth
import UIKit
import UserNotifications

/// Serialized, disk-backed reconciliation. A cancelled/failed pass retains its cursor,
/// pending measurements and per-type work; consent is scoped to server and strap.
@MainActor
@Observable
final class HealthCoordinator {
    private(set) var journal = HealthJournal()
    private(set) var busy = false
    private(set) var status = "Not connected"
    private(set) var error: String?
    private(set) var earliest: Date?
    var showWeightEntry = false
    private(set) var importingWeightHistory = false
    private(set) var importedWeightCount = 0
    let adapter = HealthAdapter()
    private let disk = HealthJournalDisk()
    private var diskRevision: UInt64 = 0
    private var activation: Task<Void, Never>?
    private var syncRequested = false
    private var scheduledSync: Task<Void, Never>?
    private var file: URL?
    private var device = ""
    private var scope = ""
    private var epoch = 0
    private var followUp: Task<Void, Never>?
    private var observation: HKObserverQuery?
    private var activeReminder: String?
    private let center = UNUserNotificationCenter.current()
    var connected: Bool { journal.connectedAt != nil }
    private(set) var rows: [WeightReading] = []
    private func refreshRows() {
        let pending = Set(journal.pendingWeights.map(\.id))
        let result = (journal.weights.filter { !$0.removed && !pending.contains($0.id) } + journal.pendingWeights.filter { !$0.removed }).sorted { $0.measuredAt > $1.measuredAt }
        if rows != result { rows = result }
    }
    var today: WeightReading? { WeightReading.preferred(rows, on: Date()) }
    var lastWeight: WeightReading? { rows.first }
    var canRemind: Bool { journal.remindWeight }

    init() {
        // Health changes and notification taps must work before Bluetooth reconnects.
        if let lastDevice = UserDefaults.standard.string(forKey: "health.lastDevice") { activate(lastDevice) }
    }
    func activate(_ device: String) {
        guard !device.isEmpty, Settings.isConfigured else { return }
        let input = "\(Settings.serverURL?.absoluteString ?? "")|\(Settings.ingestToken)|\(device)"
        let next = SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
        guard next != scope else { return }
        epoch += 1; activation?.cancel(); scheduledSync?.cancel(); scheduledSync = nil; syncRequested = false; followUp?.cancel(); followUp = nil; busy = false; importingWeightHistory = false
        if let observation { adapter.store.stop(observation) }; observation = nil
        if let activeReminder { center.removePendingNotificationRequests(withIdentifiers: [activeReminder]) }; activeReminder = nil
        scope = next; self.device = device; journal = HealthJournal(); error = nil
        file = nil; rows = []
        let generation = epoch
        activation = Task { [weak self] in
            guard let self else { return }
            do {
                // The application-support directory already exists after queue setup;
                // directory creation and all journal I/O belong to the disk actor.
                let folder = URL.applicationSupportDirectory.appendingPathComponent("HealthSync", isDirectory: true)
                let (file, saved) = try await self.disk.open(folder: folder, name: next)
                try self.valid(generation)
                self.file = file; self.journal = saved; self.refreshRows()
                self.status = self.connected ? (self.journal.paused ? "Paused" : "Ready to sync") : "Not connected"
                UserDefaults.standard.set(device, forKey: "health.lastDevice")
                self.installObserver(); self.checkSoon()
            } catch is CancellationError { }
            catch { if generation == self.epoch { self.error = "Couldn’t open saved Health sync progress. Restart Snoop to try again." } }
        }
    }
    private func persist() async throws {
        guard let file else { throw CocoaError(.fileWriteUnknown) }
        let generation = epoch
        diskRevision &+= 1
        try await disk.save(journal, to: file, revision: diskRevision)
        try valid(generation)
    }
    /// Settings remain immediately reflected in the existing UI while persistence is queued.
    private func persistSettings() {
        guard let file else { return }
        diskRevision &+= 1
        let snapshot = journal, revision = diskRevision, generation = epoch
        Task {
            do { try await disk.save(snapshot, to: file, revision: revision) }
            catch { if generation == epoch { self.error = "Couldn’t save sync settings. Try again." } }
        }
    }
    private func valid(_ generation: Int) throws {
        guard generation == epoch, !Task.isCancelled, Settings.isConfigured else { throw CancellationError() }
        let current = "\(Settings.serverURL?.absoluteString ?? "")|\(Settings.ingestToken)|\(device)"
        guard SHA256.hash(data: Data(current.utf8)).map({ String(format: "%02x", $0) }).joined() == scope else { throw CancellationError() }
    }
    func connect(steps: Bool, importWeight: Bool, exportWeight: Bool) async {
        guard adapter.available else { error = "Apple Health is unavailable on this device."; return }
        let generation = epoch
        do {
            try await adapter.request(steps: steps, importWeight: importWeight, exportWeight: exportWeight)
            try valid(generation)
            if journal.connectedAt == nil { journal.connectedAt = Date(); journal.cursor = 0; journal.pageCursor = 0; journal.snapshot = true }
            if steps != journal.exportSteps || exportWeight != journal.exportWeight { journal.snapshot = true; journal.watermark = nil; journal.pageCursor = 0 }
            journal.exportSteps = steps; journal.importWeight = importWeight; journal.exportWeight = exportWeight; journal.paused = false
            if journal.importStart == nil { journal.importStart = journal.connectedAt }
            try await persist(); installObserver(); await sync()
        } catch { self.error = error.localizedDescription }
    }
    func disconnect() {
        journal.paused = true
        journal.connectedAt = nil
        if let observation { adapter.store.stop(observation) }; observation = nil
        adapter.store.disableBackgroundDelivery(for: HealthAdapter.weightType) { _, _ in }
        persistSettings(); status = "Not connected"
    }
    func removeExports() async {
        guard !busy else { return }
        busy = true
        let generation = epoch
        defer {
            if epoch == generation {
                busy = false
                if syncRequested && scheduledSync == nil { syncRequested = false; checkSoon() }
            }
        }
        do {
            journal.paused = true; try await persist()
            try await adapter.removeExports(namespace: journal.namespace); try valid(generation)
            journal.versions = [:]; journal.deferred = [:]; journal.clearExportHistory()
            journal.cursor = 0; journal.watermark = nil; journal.pageCursor = 0; journal.snapshot = true
            disconnect()
        } catch { self.error = "Some Snoop exports could not be removed. Check Health permissions and retry." }
    }
    func pause(_ paused: Bool) {
        journal.paused = paused
        persistSettings(); status = paused ? "Paused" : "Ready to sync"; if !paused { checkSoon() }
    }
    func setReminder(_ enabled: Bool) {
        journal.remindWeight = enabled
        persistSettings()
        if !enabled { cancelReminder() } else { checkSoon() }
    }
    func openReminder(scope: String) {
        guard scope == self.scope else { return }
        showWeightEntry = true
    }
    func checkSoon() {
        guard !device.isEmpty else { return }
        let generation = epoch
        if busy { syncRequested = true }
        else if scheduledSync == nil {
            scheduledSync = Task { [weak self] in
                guard let self else { return }
                await self.sync()
                guard self.epoch == generation else { return }
                self.scheduledSync = nil
                if self.syncRequested { self.syncRequested = false; self.checkSoon() }
            }
        }
        if followUp == nil {
            followUp = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(15 * 60 + 20)) } catch { return }
                guard let self, self.epoch == generation else { return }
                await self.sync()
                if self.epoch == generation { self.followUp = nil }
            }
        }
    }
    func save(_ row: WeightReading) async throws {
        activate(device)
        guard file != nil else { throw SnoopAPI.Failure.notConfigured }
        journal.pendingWeights.removeAll { $0.id == row.id }; journal.pendingWeights.append(row)
        refreshRows(); try await persist(); cancelReminder(); showWeightEntry = false
        checkSoon()
    }
    func sync() async {
        activate(device)
        guard !busy else { syncRequested = true; return }
        guard !device.isEmpty, file != nil, Settings.isConfigured else { return }
        busy = true; error = nil
        let generation = epoch
        defer {
            if epoch == generation {
                busy = false
                if syncRequested && scheduledSync == nil { syncRequested = false; checkSoon() }
            }
        }
        do {
            let info = try await SnoopAPI.healthInfo(device); try valid(generation)
            guard journal.namespace.isEmpty || journal.namespace == info.namespace else { throw HealthAdapter.Failure.newerVersion }
            journal.namespace = info.namespace; earliest = info.earliest
            guard journal.cursor <= info.cursor else { throw HealthAdapter.Failure.newerVersion }
            // Persist every local measurement before asking Health to mirror it.
            for row in journal.pendingWeights {
                try valid(generation)
                let saved = try await SnoopAPI.saveWeight(device, row); try valid(generation)
                journal.weights.removeAll { $0.id == saved.id }; journal.weights.append(saved)
                journal.pendingWeights.removeAll { $0 == row }; refreshRows(); try await persist()
            }
            if connected && !journal.paused && journal.importWeight && adapter.available && UIApplication.shared.isProtectedDataAvailable {
                try await importWeights(generation)
            }
            try await loadWeights(generation)
            try await remind(wake: info.wakeAt, generation: generation)
            guard connected, !journal.paused else { status = connected ? "Paused" : "Not connected"; return }
            guard UIApplication.shared.isProtectedDataAvailable else { status = "Waiting to unlock"; return }
            // Bootstrap only consented periods, in small server transactions.
            if journal.exportSteps, let connectedAt = journal.connectedAt {
                for range in [HealthJournal.Range(from: connectedAt, to: Date())] + journal.allExportRanges {
                    var start = range.from
                    while !journal.paused {
                        try valid(generation); status = "Preparing steps…"
                        let result = try await SnoopAPI.prepareHealth(device, from: start, to: range.to); try valid(generation)
                        guard !result.done, let next = result.nextDay else { break }
                        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(secondsFromGMT: 0)
                        guard let date = f.date(from: next) else { throw HealthAdapter.Failure.invalidRecord }; start = date
                    }
                }
            }
            repeat {
                try valid(generation); if journal.paused { return }
                status = "Syncing Apple Health…"
                let page = try await SnoopAPI.healthPage(device, cursor: journal.watermark == nil ? (journal.snapshot ? 0 : journal.cursor) : journal.pageCursor, watermark: journal.watermark, snapshot: journal.snapshot)
                try valid(generation)
                guard page.namespace == journal.namespace else { throw HealthAdapter.Failure.newerVersion }
                journal.watermark = page.watermark; try await persist()
                for record in page.records {
                    try valid(generation); if journal.paused { return }
                    try await export(record, generation: generation)
                }
                journal.pageCursor = page.nextCursor
                if page.done { journal.cursor = page.watermark; journal.watermark = nil; journal.snapshot = false }
                try await persist()
                if page.done { break }
                await Task.yield()
            } while true
            for record in journal.deferred.values.sorted(by: { $0.sequence < $1.sequence }) {
                try valid(generation); if journal.paused { return }
                try await export(record, generation: generation)
            }
            if journal.exportWeight { try await adapter.removeWeightConflicts(namespace: journal.namespace); try valid(generation) }
            journal.lastSync = Date(); try await persist()
            status = journal.deferred.isEmpty ? "Up to date" : "Some exports are waiting"
        } catch is CancellationError { }
        catch {
            if generation == epoch { self.error = error.localizedDescription; status = "Sync paused · retry available" }
        }
    }
    private func export(_ record: HealthRecord, generation: Int) async throws {
        if record.domain == "steps" && !journal.exportSteps || record.domain == "weight" && !journal.exportWeight { return }
        var eligible = journal.eligible(record)
        // Retained Health records re-enrol after reinstall, even outside the new
        // connection date. A missing record never enrolls by absence alone.
        if !eligible && journal.snapshot && adapter.available {
            let owned = try await adapter.owned(record, namespace: journal.namespace); try valid(generation)
            eligible = !owned.isEmpty
        }
        guard eligible else { return }
        if let prior = journal.versions[record.id], prior >= record.version { journal.deferred.removeValue(forKey: record.id); return }
        let enabled = record.domain == "steps" ? journal.exportSteps : record.domain == "weight" ? journal.exportWeight : true
        guard enabled, adapter.canWrite(record.domain) else { journal.deferred[record.id] = record; try await persist(); return }
        if record.domain == "weight", !record.removed {
            // Read permission is intentionally opaque. Never promise that an empty
            // query proves an empty day; the person explicitly opts into exports.
            let foreign = try await adapter.existingWeight(on: record.startTs); try valid(generation)
            if !foreign.isEmpty {
                journal.acknowledge(record); try await persist(); return
            }
        }
        guard !journal.paused else { throw CancellationError() }
        try await adapter.apply(record, namespace: journal.namespace); try valid(generation)
        journal.acknowledge(record); try await persist()
    }
    private func loadWeights(_ generation: Int) async throws {
        var watermark: Int64?
        do {
            repeat {
                let page = try await SnoopAPI.weightChanges(device, cursor: journal.weightCursor ?? 0, watermark: watermark)
                try valid(generation)
                var saved = Dictionary(journal.weights.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.version >= b.version ? a : b })
                for row in page.rows where (saved[row.id]?.version ?? -1) <= row.version { saved[row.id] = row }
                if !page.rows.isEmpty { journal.weights = Array(saved.values); refreshRows() }
                journal.weightCursor = page.nextCursor
                try await persist()
                if page.done { return }
                watermark = page.watermark
            } while true
        } catch SnoopAPI.Failure.http(404) {
            try await loadAllWeights(generation)
        } catch SnoopAPI.Failure.server(404, _) {
            try await loadAllWeights(generation)
        }
    }
    private func loadAllWeights(_ generation: Int) async throws {
        var loaded: [WeightReading] = []; var after = ""
        repeat {
            try valid(generation)
            let rows = try await SnoopAPI.weights(device, from: Date(timeIntervalSince1970: 0), to: Date().addingTimeInterval(300), after: after)
            try valid(generation); loaded += rows
            guard rows.count == 250, let last = rows.last else { break }; after = last.id
        } while true
        journal.weights = loaded; refreshRows(); try await persist()
    }
    private func importWeights(_ generation: Int, allowWhilePaused: Bool = false) async throws {
        guard let from = journal.importStart ?? journal.connectedAt else { return }
        repeat {
            try valid(generation); if (journal.paused && !allowWhilePaused) || !journal.importWeight { return }
            let changes = try await adapter.weightChanges(anchor: journal.anchor, from: from, to: nil); try valid(generation)
            for row in changes.readings {
                guard journal.permitsWeightImport(at: row.measuredAt) else { continue }
                try valid(generation)
                guard !journal.paused || allowWhilePaused else { throw CancellationError() }
                if journal.weights.contains(where: { $0.id == row.id && $0.kg == row.kg && !$0.removed }) { continue }
                let saved = try await SnoopAPI.saveWeight(device, row); try valid(generation)
                journal.weights.removeAll { $0.id == saved.id }; journal.weights.append(saved); refreshRows()
                if importingWeightHistory && journal.pendingWeightImport?.contains(saved.measuredAt) == true { importedWeightCount += 1 }
                // Preserve per-reading receipts before advancing the Health anchor;
                // repeated short background windows can finish a large import.
                try await persist()
            }
            try await SnoopAPI.removeImportedWeights(device, ids: changes.deleted); try valid(generation)
            let deleted = Set(changes.deleted)
            journal.weights.removeAll { $0.source == "health" && deleted.contains($0.id) }
            refreshRows(); journal.anchor = changes.anchor; try await persist()
            if !changes.more { journal.pendingWeightImport = nil; try await persist(); return }
        } while true
    }
    private func remind(wake: Date?, generation: Int) async throws {
        if today != nil || !journal.remindWeight { cancelReminder(); return }
        // Even without importing history, use visible Health weight to suppress the
        // prompt when weight sharing was enabled. Locked reads wait for another wake.
        if connected && (journal.importWeight || journal.exportWeight) {
            guard UIApplication.shared.isProtectedDataAvailable else { return }
            if !(try await adapter.existingWeight(on: Date())).isEmpty { try valid(generation); cancelReminder(); return }
        }
        let key = Self.dayKey(Date())
        guard journal.remindWeight, let delivery = WeightReminderPolicy.delivery(now: Date(), confirmedWake: wake, enabledAt: journal.reminderEnabledAt, hasWeight: today != nil, alreadyReminded: journal.remindedDays.contains(key)) else { return }
        let settings = await center.notificationSettings(); try valid(generation)
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let identifier = "snoop.weight.\(scope).\(key)"
        let content = UNMutableNotificationContent(); content.title = "Good morning"; content.body = "Ready to log your weight?"; content.sound = .default
        content.threadIdentifier = "snoop.weight"; content.userInfo = ["destination": "weight", "scope": scope, "day": key]
        // Save deduplication before scheduling. A crash can skip one reminder, never
        // multiply it. Scheduling failure rolls the receipt back for a later retry.
        journal.remindedDays.insert(key); try await persist()
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, delivery.timeIntervalSinceNow), repeats: false)))
            try valid(generation); activeReminder = identifier
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            if generation == epoch { journal.remindedDays.remove(key); try await persist() }
            throw error
        }
    }
    private func cancelReminder() {
        let identifier = "snoop.weight.\(scope).\(Self.dayKey(Date()))"
        center.removePendingNotificationRequests(withIdentifiers: [identifier]); center.removeDeliveredNotifications(withIdentifiers: [identifier]); activeReminder = nil
    }
    static func dayKey(_ date: Date) -> String { DayKey.string(date) }
    private func installObserver() {
        guard connected, (journal.importWeight || journal.exportWeight), adapter.available, observation == nil else { return }
        let generation = epoch
        let query = HKObserverQuery(sampleType: HealthAdapter.weightType, predicate: nil) { [weak self] _, completion, error in
            let done = CompletionOnce(completion)
            Task { @MainActor in
                if error == nil, let self, self.epoch == generation { await self.sync() }
                done.call()
            }
        }
        observation = query; adapter.store.execute(query)
        adapter.store.enableBackgroundDelivery(for: HealthAdapter.weightType, frequency: .immediate) { _, _ in }
    }
    struct Preview { var sleep = 0; var workouts = 0; var stepDays: Set<String> = []; var weights = 0; var already = 0 }
    func preview(_ range: HealthJournal.Range) async throws -> Preview {
        guard !busy else { throw PreviewFailure.busy }
        busy = true
        let generation = epoch
        defer { if generation == epoch { busy = false; if syncRequested { syncRequested = false; checkSoon() } } }
        if journal.exportSteps {
            var start = range.from
            while true {
                try valid(generation)
                let prepared = try await SnoopAPI.prepareHealth(device, from: start, to: range.to)
                try valid(generation)
                guard !prepared.done, let next = prepared.nextDay else { break }
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(secondsFromGMT: 0)
                guard let date = f.date(from: next) else { throw HealthAdapter.Failure.invalidRecord }; start = date
            }
        }
        var result = Preview(); var cursor: Int64 = 0; var watermark: Int64?
        repeat {
            let page = try await SnoopAPI.healthPage(device, cursor: cursor, watermark: watermark, snapshot: true); try valid(generation)
            watermark = page.watermark
            for r in page.records where range.contains(r.eligibilityDate) && !r.removed {
                if journal.versions[r.id] == r.version { result.already += 1 }
                switch r.domain {
                case "sleep": result.sleep += 1
                case "workout": result.workouts += 1
                case "steps": if journal.exportSteps { result.stepDays.insert(Self.dayKey(r.startTs)) }
                case "weight": if journal.exportWeight { result.weights += 1 }
                default: break
                }
            }
            cursor = page.nextCursor; if page.done { break }
        } while true
        return result
    }
    func previewWeightImport(_ range: HealthJournal.Range) async throws -> WeightImportPreview {
        let generation = epoch
        guard connected, journal.importWeight else { throw WeightImportFailure.notEnabled }
        let readings = try await adapter.weightReadings(in: range)
        try valid(generation)
        return WeightImportPreview(readings: readings, savedIDs: Set(rows.map(\.id)), range: range)
    }
    /// Selected weights only. Export selections/cursors and the global pause state stay intact.
    func importWeightHistory(_ range: HealthJournal.Range) async throws -> Int {
        let generation = epoch
        while busy { try await Task.sleep(for: .milliseconds(150)); try valid(generation) }
        try valid(generation)
        guard connected, journal.importWeight else { throw WeightImportFailure.notEnabled }
        busy = true; importingWeightHistory = true; importedWeightCount = 0; error = nil
        defer { if epoch == generation { busy = false; importingWeightHistory = false; if syncRequested { syncRequested = false; checkSoon() } } }
        let previous = Set(rows.filter { range.contains($0.measuredAt) }.map(\.id))
        do {
            let info = try await SnoopAPI.healthInfo(device); try valid(generation)
            guard journal.namespace.isEmpty || journal.namespace == info.namespace, journal.cursor <= info.cursor else { throw HealthAdapter.Failure.newerVersion }
            journal.namespace = info.namespace
            journal.approveWeightImport(range); try await persist()
            status = "Importing weigh-ins…"
            try await importWeights(generation, allowWhilePaused: true)
            try valid(generation)
            let count = rows.filter { $0.source == "health" && range.contains($0.measuredAt) && !previous.contains($0.id) }.count
            cancelReminderIfWeighed()
            status = journal.paused ? "Paused" : "Weight history imported"
            return count
        } catch {
            if epoch == generation { self.error = error.localizedDescription; status = "Weight import interrupted" }
            throw error
        }
    }
    private func cancelReminderIfWeighed() { if today != nil { cancelReminder() } }
    enum WeightImportFailure: LocalizedError {
        case notEnabled
        var errorDescription: String? { "Enable weight imports in the Apple Health connection to continue." }
    }
    enum PreviewFailure: LocalizedError { case busy; var errorDescription: String? { "Wait for the current sync to finish, then preview again." } }
    func backfill(_ range: HealthJournal.Range) async throws {
        guard !busy else { throw PreviewFailure.busy }
        journal.backfill(range); journal.paused = false
        try await persist(); await sync()
    }
}
