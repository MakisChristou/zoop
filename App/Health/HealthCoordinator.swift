import Observation
import ZoopData
import CryptoKit
import Foundation
import HealthKit
import ZoopHealth
import UIKit

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
    var onReminderChange: (() -> Void)?
    private var knownHealthWeightDay: String?
    var reminderScope: String? {
        guard file != nil, Settings.isConfigured else { return nil }
        return Settings.healthScope(device: device) == scope ? scope : nil
    }
    var reminderDevice: String { device }
    var reminderWeightDays: Set<String> {
        var days = Set(rows.map { Self.dayKey($0.measuredAt) })
        if let knownHealthWeightDay { days.insert(knownHealthWeightDay) }
        return days
    }
    private var unlockObserver: NSObjectProtocol?
    var connected: Bool { journal.connectedAt != nil }
    private(set) var rows: [WeightReading] = []
    private func refreshRows() {
        let pending = Set(journal.pendingWeights.map(\.id))
        let result = (journal.weights.filter { !$0.removed && !pending.contains($0.id) } + journal.pendingWeights.filter { !$0.removed }).sorted { $0.measuredAt > $1.measuredAt }
        if rows != result { rows = result }
        onReminderChange?()
    }
    var today: WeightReading? { WeightReading.preferred(rows, on: Date()) }
    var lastWeight: WeightReading? { WeightReading.latest(rows) }
    var canRemind: Bool { journal.remindWeight }

    init() {
        unlockObserver = NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshReminderCompletion(); self?.checkSoon() }
        }
        // Health changes and notification taps must work before Bluetooth reconnects.
        if let lastDevice = UserDefaults.standard.string(forKey: "health.lastDevice") { activate(lastDevice) }
    }
    func activate(_ device: String) {
        guard !device.isEmpty, Settings.isConfigured else { deactivate(); return }
        let next = Settings.healthScope(device: device)
        guard next != scope else { return }
        epoch += 1; activation?.cancel(); scheduledSync?.cancel(); scheduledSync = nil; syncRequested = false; followUp?.cancel(); followUp = nil; busy = false; importingWeightHistory = false
        if let observation { adapter.store.stop(observation) }; observation = nil
        knownHealthWeightDay = nil
        scope = next; self.device = device; journal = HealthJournal(); error = nil
        file = nil; rows = []; onReminderChange?()
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
                self.installObserver(); await self.refreshReminderCompletion(); self.checkSoon()
            } catch is CancellationError { }
            catch { if generation == self.epoch { self.error = "Couldn’t open saved Health sync progress. Restart Zoop to try again." } }
        }
    }
    func eraseLocal(scopes: [String]) async throws {
        deactivate()
        try await disk.erase(folder: URL.applicationSupportDirectory.appendingPathComponent("HealthSync", isDirectory: true), names: scopes)
    }
    private func deactivate() {
        epoch += 1; activation?.cancel(); scheduledSync?.cancel(); followUp?.cancel()
        activation = nil; scheduledSync = nil; followUp = nil; syncRequested = false
        if let observation { adapter.store.stop(observation) }; observation = nil
        scope = ""; device = ""; file = nil; journal = HealthJournal(); rows = []
        knownHealthWeightDay = nil; busy = false; importingWeightHistory = false
        status = "Not connected"; error = nil; onReminderChange?()
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
        guard Settings.healthScope(device: device) == scope else { throw CancellationError() }
    }
    func connect(steps: Bool, importWeight: Bool, exportWeight: Bool, resumeSync: Bool = true) async {
        guard adapter.available else { error = "Apple Health is unavailable on this device."; return }
        let generation = epoch
        do {
            if !connected || (steps && !journal.exportSteps) || (importWeight && !journal.importWeight) || (exportWeight && !journal.exportWeight)
                || (steps && !adapter.canWrite("steps")) || (exportWeight && !adapter.canWrite("weight")) {
                try await adapter.request(steps: steps, importWeight: importWeight, exportWeight: exportWeight)
            }
            try valid(generation)
            if journal.connectedAt == nil { journal.connectedAt = Date(); journal.cursor = 0; journal.pageCursor = 0; journal.snapshot = true }
            if steps != journal.exportSteps || exportWeight != journal.exportWeight { journal.snapshot = true; journal.watermark = nil; journal.pageCursor = 0 }
            journal.exportSteps = steps; journal.importWeight = importWeight; journal.exportWeight = exportWeight
            if resumeSync { journal.paused = false }
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
        } catch { self.error = "Some Zoop exports could not be removed. Check Health permissions and retry." }
    }
    func pause(_ paused: Bool) {
        journal.paused = paused
        persistSettings(); status = paused ? "Paused" : "Ready to sync"; if !paused { checkSoon() }
    }
    func setReminder(_ enabled: Bool) {
        if enabled && !journal.remindWeight { journal.reminderEnabledAt = Date() }
        journal.remindWeight = enabled
        persistSettings()
        onReminderChange?()
    }
    func openReminder(scope: String) {
        guard scope == reminderScope, !reminderWeightDays.contains(Self.dayKey(Date())) else { return }
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
        guard file != nil else { throw ZoopAPI.Failure.notConfigured }
        try WeightEntryPolicy.validate(row, existing: rows)
        journal.pendingWeights.removeAll { $0.id == row.id }; journal.pendingWeights.append(row)
        refreshRows(); try await persist()
        // Editing or adding an older reading must not cancel today’s check-in.
        if today != nil { cancelReminder() }
        showWeightEntry = false
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
            let info = try await ZoopAPI.healthInfo(device); try valid(generation)
            guard journal.namespace.isEmpty || journal.namespace == info.namespace else { throw HealthAdapter.Failure.newerVersion }
            journal.namespace = info.namespace; earliest = info.earliest
            guard journal.cursor <= info.cursor else { throw HealthAdapter.Failure.newerVersion }
            // A successful response can revoke a previously eligible wake.
            if journal.lastConfirmedWake != info.wakeAt { journal.lastConfirmedWake = info.wakeAt; try await persist() }
            try await loadWeights(generation)
            await refreshReminderCompletion()
            // Persist every local measurement before asking Health to mirror it.
            for row in journal.pendingWeights {
                try valid(generation)
                let saved = try await ZoopAPI.saveWeight(device, row); try valid(generation)
                journal.weights.removeAll { $0.id == saved.id }; journal.weights.append(saved)
                journal.pendingWeights.removeAll { $0 == row }; refreshRows(); try await persist()
            }
            if connected && !journal.paused && journal.importWeight && adapter.available && UIApplication.shared.isProtectedDataAvailable {
                try await importWeights(generation)
            }
            if today != nil { cancelReminder() }
            guard connected, !journal.paused else { status = connected ? "Paused" : "Not connected"; return }
            guard UIApplication.shared.isProtectedDataAvailable else { status = "Waiting to unlock"; return }
            // Bootstrap only consented periods, in small server transactions.
            if journal.exportSteps, let connectedAt = journal.connectedAt {
                for range in [HealthJournal.Range(from: connectedAt, to: Date())] + journal.allExportRanges {
                    var start = range.from
                    while !journal.paused {
                        try valid(generation); status = "Preparing steps…"
                        let result = try await ZoopAPI.prepareHealth(device, from: start, to: range.to); try valid(generation)
                        guard !result.done, let next = result.nextDay else { break }
                        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(secondsFromGMT: 0)
                        guard let date = f.date(from: next) else { throw HealthAdapter.Failure.invalidRecord }; start = date
                    }
                }
            }
            repeat {
                try valid(generation); if journal.paused { return }
                status = "Syncing Apple Health…"
                let page = try await ZoopAPI.healthPage(device, cursor: journal.watermark == nil ? (journal.snapshot ? 0 : journal.cursor) : journal.pageCursor, watermark: journal.watermark, snapshot: journal.snapshot)
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
            if generation == epoch {
                self.error = error.localizedDescription; status = "Sync paused · retry available"
                await refreshReminderCompletion()
            }
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
                let page = try await ZoopAPI.weightChanges(device, cursor: journal.weightCursor ?? 0, watermark: watermark)
                try valid(generation)
                var saved = Dictionary(journal.weights.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.version >= b.version ? a : b })
                for row in page.rows where (saved[row.id]?.version ?? -1) <= row.version { saved[row.id] = row }
                if !page.rows.isEmpty { journal.weights = Array(saved.values); refreshRows() }
                journal.weightCursor = page.nextCursor
                try await persist()
                if page.done { return }
                watermark = page.watermark
            } while true
        } catch ZoopAPI.Failure.http(404) {
            try await loadAllWeights(generation)
        } catch ZoopAPI.Failure.server(404, _) {
            try await loadAllWeights(generation)
        }
    }
    private func loadAllWeights(_ generation: Int) async throws {
        var loaded: [WeightReading] = []; var after = ""
        repeat {
            try valid(generation)
            let rows = try await ZoopAPI.weights(device, from: Date(timeIntervalSince1970: 0), to: Date().addingTimeInterval(300), after: after)
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
                let saved = try await ZoopAPI.saveWeight(device, row); try valid(generation)
                journal.weights.removeAll { $0.id == saved.id }; journal.weights.append(saved); refreshRows()
                if importingWeightHistory && journal.pendingWeightImport?.contains(saved.measuredAt) == true { importedWeightCount += 1 }
                // Preserve per-reading receipts before advancing the Health anchor;
                // repeated short background windows can finish a large import.
                try await persist()
            }
            try await ZoopAPI.removeImportedWeights(device, ids: changes.deleted); try valid(generation)
            let deleted = Set(changes.deleted)
            journal.weights.removeAll { $0.source == "health" && deleted.contains($0.id) }
            refreshRows(); journal.anchor = changes.anchor; try await persist()
            if !changes.more { journal.pendingWeightImport = nil; try await persist(); return }
        } while true
    }
    /// Runs independently of the backend so visible Health measurements can cancel
    /// today's scheduled reminder even during an API outage.
    func refreshReminderCompletion() async {
        let generation = epoch
        if connected && (journal.importWeight || journal.exportWeight), UIApplication.shared.isProtectedDataAvailable {
            do {
                let queriedDay = Date()
                let values = try await adapter.existingWeight(on: queriedDay)
                try valid(generation)
                knownHealthWeightDay = values.isEmpty ? nil : Self.dayKey(queriedDay)
            } catch { /* Keep known completion while Health is temporarily unavailable. */ }
        }
        if generation == epoch { onReminderChange?() }
    }
    private func cancelReminder() { onReminderChange?() }
    static func dayKey(_ date: Date) -> String { DayKey.string(date) }
    private func installObserver() {
        guard connected, (journal.importWeight || journal.exportWeight), adapter.available, observation == nil else { return }
        let generation = epoch
        let query = HKObserverQuery(sampleType: HealthAdapter.weightType, predicate: nil) { [weak self] _, completion, error in
            let done = CompletionOnce(completion)
            Task { @MainActor in
                if error == nil, let self, self.epoch == generation { await self.refreshReminderCompletion(); await self.sync() }
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
                let prepared = try await ZoopAPI.prepareHealth(device, from: start, to: range.to)
                try valid(generation)
                guard !prepared.done, let next = prepared.nextDay else { break }
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(secondsFromGMT: 0)
                guard let date = f.date(from: next) else { throw HealthAdapter.Failure.invalidRecord }; start = date
            }
        }
        var result = Preview(); var cursor: Int64 = 0; var watermark: Int64?
        repeat {
            let page = try await ZoopAPI.healthPage(device, cursor: cursor, watermark: watermark, snapshot: true); try valid(generation)
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
            let info = try await ZoopAPI.healthInfo(device); try valid(generation)
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
