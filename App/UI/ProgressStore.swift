import Foundation
import Observation

/// Progress loads only when opened. Range/metric taps in Trends do no extra work.
@MainActor @Observable final class ProgressStore {
    typealias Loader = @Sendable (String) async throws -> SnoopAPI.ProgressSummary
    private(set) var summary: SnoopAPI.ProgressSummary?
    private(set) var error: String?
    private(set) var loading = false
    private var scope: String?
    private var request = UUID()
    private let loader: Loader

    init(loader: @escaping Loader = { try await SnoopAPI.progress(deviceId: $0) }) { self.loader = loader }

    func reload(device: String, connection: String, isCurrent: () -> Bool = { true }) async {
        let source = device + "|" + connection, id = UUID()
        request = id
        if scope != source { scope = source; summary = nil; error = nil }
        guard !device.isEmpty else { loading = false; error = "Connect your WHOOP to see your progress."; return }
        loading = true
        defer { if request == id { loading = false } }
        do {
            let value = try await loader(device)
            guard !Task.isCancelled, request == id, scope == source, isCurrent() else { return }
            summary = value; error = nil
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, request == id, scope == source, isCurrent() else { return }
            self.error = "Couldn’t update progress. Pull down to try again."
        }
    }
}
