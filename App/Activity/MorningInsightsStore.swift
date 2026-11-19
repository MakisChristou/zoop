import Foundation
import Observation

/// The brief follows analysis independently of the larger Today-history request.
/// Pending results are short-lived; hidden/background screens stop polling.
@MainActor @Observable final class MorningInsightsStore {
    struct Scope: Equatable {
        let device: String
        let day: Date
        let connection: String
        let timezone: String
    }
    struct FollowKey: Equatable {
        let scope: Scope
        let active: Bool
    }
    private(set) var value: MorningInsights?
    private(set) var failed = false
    private(set) var loading = false
    @ObservationIgnored private let fetch: (String, Date) async throws -> MorningInsights
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    // Scoped reads must observe the first scope assignment, even before value exists.
    private var scope: Scope?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var monitorID = UUID()
    @ObservationIgnored private var pollWait: Task<Void, Error>?
    @ObservationIgnored private var wakeRevision = 0

    private enum Cadence {
        static let updating: Duration = .seconds(5)
        static let awaitingSync: Duration = .seconds(30)
        static let retry: Duration = .seconds(15)
        static let settled: Duration = .seconds(300)
    }

    init(fetch: @escaping (String, Date) async throws -> MorningInsights = { try await ZoopAPI.morningInsights(deviceId: $0, day: $1) },
         sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.fetch = fetch; self.sleep = sleep
    }

    /// Called from a visibility/scene-scoped SwiftUI task. No whole-day refetch is
    /// needed to replace the server's transient `updating` response.
    func follow(_ scope: Scope, isCurrent: @escaping @MainActor () -> Bool = { true }) async {
        pollWait?.cancel(); pollWait = nil
        let monitor = UUID(); monitorID = monitor
        defer {
            if monitorID == monitor { pollWait?.cancel(); pollWait = nil }
        }
        while !Task.isCancelled, monitorID == monitor, isCurrent() {
            await reload(scope, isCurrent: isCurrent)
            guard !Task.isCancelled, monitorID == monitor, isCurrent() else { return }
            let revision = wakeRevision, delay = refreshDelay, sleep = sleep
            let wait = Task { try await sleep(delay) }; pollWait = wait
            do {
                try await withTaskCancellationHandler {
                    try await wait.value
                } onCancel: { wait.cancel() }
            } catch {
                // An upload/correction may change a settled result to Updating
                // while this monitor is sleeping. Resume at the shorter cadence.
                guard wakeRevision != revision else { return }
            }
        }
    }

    func value(for scope: Scope) -> MorningInsights? { self.scope == scope ? value : nil }
    func failed(for scope: Scope) -> Bool { self.scope == scope && failed }

    func reload(_ next: Scope, isCurrent: @MainActor () -> Bool = { true }) async {
        guard !Task.isCancelled, isCurrent() else { return }
        guard !next.device.isEmpty, !next.connection.isEmpty else { stop(clear: true); return }
        if scope != next { scope = next; value = nil; failed = false }
        let request = UUID(); requestID = request; loading = true
        defer { if requestID == request { loading = false } }
        do {
            let response = try await fetch(next.device, next.day)
            guard !Task.isCancelled, requestID == request, scope == next, isCurrent() else { return }
            let previousDelay = refreshDelay
            value = response; failed = false
            shortenWait(after: previousDelay)
        } catch {
            guard !Task.isCancelled, requestID == request, scope == next, isCurrent() else { return }
            // A failed request must not leave an old Updating label on screen forever.
            let previousDelay = refreshDelay
            value = nil; failed = true
            shortenWait(after: previousDelay)
        }
    }

    func stop(clear: Bool = false) {
        monitorID = UUID(); requestID = UUID(); loading = false
        pollWait?.cancel(); pollWait = nil
        if clear { scope = nil; value = nil; failed = false }
    }

    private var refreshDelay: Duration {
        // A superseding request can be cancelled before either response publishes.
        // An empty brief is not a settled result; retry it promptly while visible.
        if failed || value == nil { return Cadence.retry }
        switch value?.state {
        case "updating": return Cadence.updating
        case "awaiting_sync": return Cadence.awaitingSync
        default: return Cadence.settled
        }
    }

    private func shortenWait(after previousDelay: Duration) {
        guard refreshDelay < previousDelay else { return }
        wakeRevision &+= 1
        pollWait?.cancel()
    }
}
