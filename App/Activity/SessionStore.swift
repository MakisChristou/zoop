import Foundation
import Observation

/// Shared correction lifecycle. One publication per response, cancellation-safe
/// range loads, and bounded polling of affected identities rather than whole history.
@MainActor @Observable
final class SessionStore<Endpoint: SessionEndpoint> {
    private(set) var items: [Endpoint.Record] = []
    private(set) var changeToken = 0
    private(set) var notice: String?
    private(set) var refreshError: String?
    private(set) var undoId: String?
    private var device: String?
    private var connection = ""
    private var epoch = 0
    private var refreshes: [String: UUID] = [:]
    private var followUp: Task<Void, Never>?
    private var undoRequest: WorkoutCorrection?

    func reload(device: String, from: Date? = nil, to: Date? = nil) async throws {
        activate(device)
        let snapshot = epoch
        let key = "\(from?.timeIntervalSince1970 ?? 0)-\(to?.timeIntervalSince1970 ?? 0)"
        let request = UUID(); refreshes[key] = request
        defer { if refreshes[key] == request { refreshes.removeValue(forKey: key) } }
        let rows = try await Endpoint.list(device: device, from: from, to: to)
        guard !Task.isCancelled, self.device == device, epoch == snapshot,
              Settings.connectionID == connection, refreshes[key] == request else { return }
        var next = items
        let ids = Set(rows.map(\.id))
        if let from, let to {
            next.removeAll { ($0.endTs > from && $0.startTs < to) || ids.contains($0.id) }
            next += rows
        } else if rows.count < Endpoint.limit { next = rows }
        else if let oldest = rows.last?.startTs {
            next.removeAll { $0.startTs >= oldest || ids.contains($0.id) }; next += rows
        }
        items = next.sorted { $0.startTs > $1.startTs }; refreshError = nil
    }
    func save(device: String, command: WorkoutCorrection) async throws {
        activate(device); epoch += 1
        let scope = connection, requestEpoch = epoch
        let receipt = try await Endpoint.save(device: device, command: command)
        guard self.device == device, epoch == requestEpoch, connection == scope, Settings.connectionID == scope else { return }
        epoch += 1
        let generation = epoch
        followUp?.cancel()
        let removed = Set(receipt.workoutIds + command.targets.map(\.id))
        items.removeAll { removed.contains($0.id) }
        notice = command.action == "remove" ? "\(Endpoint.noun) removed" : command.action == "undo" ? "Change undone" : "\(Endpoint.noun) saved"
        undoId = command.action == "undo" ? nil : receipt.operationId
        undoRequest = nil; changeToken += 1
        do { try await reload(device: device) } catch { refreshError = Endpoint.refreshMessage }
        guard epoch == generation, self.device == device, Settings.connectionID == scope else { return }
        followUp = Task { [weak self] in
            for attempt in 0..<30 {
                if attempt > 0 { do { try await Task.sleep(for: .seconds(2)) } catch { return } }
                guard let self, !Task.isCancelled, self.epoch == generation, self.connection == Settings.connectionID else { return }
                do {
                    var changed: [Endpoint.Record] = []
                    for id in receipt.workoutIds { changed.append(try await Endpoint.get(device: device, id: id)) }
                    guard !Task.isCancelled, self.epoch == generation else { return }
                    let ids = Set(changed.map(\.id))
                    self.items = (self.items.filter { !ids.contains($0.id) } + changed.filter(\.isActive)).sorted { $0.startTs > $1.startTs }
                    if !changed.contains(where: \.needsMetrics) {
                        await SnoopAPI.invalidateReads()
                        guard !Task.isCancelled, self.epoch == generation else { return }
                        self.refreshError = nil; self.changeToken += 1
                        return
                    }
                } catch is CancellationError { return }
                catch { self.refreshError = Endpoint.refreshMessage }
            }
            guard let self, self.epoch == generation else { return }
            self.refreshError = Endpoint.refreshMessage
        }
    }
    func undo(device: String, id: String) async throws {
        if undoRequest?.undoId != id { undoRequest = WorkoutCorrection(action: "undo", undoId: id) }
        guard let request = undoRequest else { return }
        try await save(device: device, command: request)
    }
    func dismissNotice() { notice = nil; undoId = nil; undoRequest = nil }
    private func activate(_ serial: String) {
        guard device != serial || connection != Settings.connectionID else { return }
        followUp?.cancel(); device = serial; connection = Settings.connectionID
        epoch += 1; items = []; refreshes = [:]; dismissNotice()
    }
}
