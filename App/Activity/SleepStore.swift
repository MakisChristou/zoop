import Foundation
import Combine

/// One effective session collection for Today, Activity, Steps, and open details.
/// Epochs discard reads begun before a save. Only a server receipt confirms a save.
@MainActor
final class SleepStore: ObservableObject {
    @Published private(set) var items: [SnoopAPI.SleepSession] = []
    @Published private(set) var changeToken = 0
    @Published private(set) var notice: String?
    @Published private(set) var refreshError: String?
    @Published private(set) var undoId: String?
    private var device: String?
    private var epoch = 0
    private var refreshes: [String: UUID] = [:]
    private var followUp: Task<Void, Never>?
    private var undoRequest: WorkoutCorrection?
    private static let refreshDelay: Duration = .seconds(2)
    private static let refreshAttempts = 30

    func reload(device: String, from: Date? = nil, to: Date? = nil) async throws {
        activate(device)
        let snapshot = epoch
        let key = "\(from?.timeIntervalSince1970 ?? 0)-\(to?.timeIntervalSince1970 ?? 0)"
        let request = UUID()
        refreshes[key] = request
        let rows = try await SnoopAPI.sleepSessions(deviceId: device, limit: 1000, from: from, to: to)
        guard !Task.isCancelled, self.device == device, epoch == snapshot, refreshes[key] == request else { return }
        if let from, let to {
            items.removeAll { $0.endTs > from && $0.startTs < to }
            let ids = Set(rows.map(\.id))
            items.removeAll { ids.contains($0.id) }
            items += rows
        } else if rows.count < 1000 { items = rows }
        else if let oldest = rows.last?.startTs {
            let ids = Set(rows.map(\.id))
            items.removeAll { $0.startTs >= oldest || ids.contains($0.id) }
            items += rows
        }
        items.sort { $0.startTs > $1.startTs }
        refreshError = nil
    }

    func save(device: String, command: WorkoutCorrection) async throws {
        activate(device)
        epoch += 1
        let receipt = try await SnoopAPI.correctSleep(deviceId: device, command: command)
        guard self.device == device else { return }
        epoch += 1
        items.removeAll { receipt.workoutIds.contains($0.id) }
        notice = command.action == "remove" ? "Sleep removed" : command.action == "undo" ? "Change undone" : "Sleep saved"
        undoId = command.action == "undo" ? nil : receipt.operationId
        undoRequest = nil
        changeToken += 1
        await refreshAfterSave(device: device, ids: receipt.workoutIds)
        followUp?.cancel()
        followUp = Task { [weak self] in
            for _ in 0..<Self.refreshAttempts {
                do { try await Task.sleep(for: Self.refreshDelay) } catch { return }
                guard let self, self.device == device else { return }
                await self.refreshAfterSave(device: device, ids: receipt.workoutIds)
                if !self.items.contains(where: { $0.metricsPending == true }),
                   let processing = try? await SnoopAPI.processing(deviceId: device), processing.pendingAnalysis == 0 {
                    self.changeToken += 1
                    return
                }
            }
        }
    }

    func undo(device: String, id: String) async throws {
        if undoRequest?.undoId != id { undoRequest = WorkoutCorrection(action: "undo", undoId: id) }
        guard let request = undoRequest else { return }
        try await save(device: device, command: request)
    }

    func dismissNotice() { notice = nil; undoId = nil; undoRequest = nil }

    private func activate(_ serial: String) {
        guard device != serial else { return }
        followUp?.cancel(); device = serial; epoch += 1; items = []; refreshes = [:]
        dismissNotice()
    }

    private func refreshAfterSave(device: String, ids: [Int64]) async {
        let snapshot = epoch
        do {
            try await reload(device: device)
            for id in ids {
                let row = try await SnoopAPI.sleepSession(deviceId: device, id: id)
                guard !Task.isCancelled, self.device == device, epoch == snapshot else { return }
                items.removeAll { $0.id == id }
                if row.isActive { items.append(row) }
            }
            items.sort { $0.startTs > $1.startTs }
        }
        catch { refreshError = "Saved. Reconnect to refresh sleep." }
    }
}
