import Foundation
import Observation
import ZoopData

/// Range selection never loads history. Refreshes replace every prepared range together.
@MainActor @Observable final class TrendStore {
    typealias NightsLoader = @Sendable (String) async throws -> [ZoopAPI.Night]
    typealias DaysLoader = @Sendable (String) async throws -> [ZoopAPI.Day]
    private(set) var snapshot = TrendSnapshot()
    private(set) var error: String?
    private(set) var loading = false
    private var requestID = UUID()
    private var scope: String?
    private let loadNights: NightsLoader
    private let loadDays: DaysLoader

    init(loadNights: @escaping NightsLoader = { try await ZoopAPI.nights(deviceId: $0, limit: TrendRange.all.days, summary: true) },
         loadDays: @escaping DaysLoader = { try await ZoopAPI.days(deviceId: $0, limit: TrendRange.all.days) }) {
        self.loadNights = loadNights; self.loadDays = loadDays
    }

    func reload(device: String, connection: String, now: Date = Date(), calendar: Calendar = .current, isCurrent: () -> Bool = { true }) async {
        let source = device + "|" + connection, request = UUID()
        requestID = request
        loading = false
        if scope != source { scope = source; snapshot = TrendSnapshot(); error = nil }
        guard !device.isEmpty else { error = "Connect your WHOOP to load trends."; return }
        loading = true
        defer { if requestID == request { loading = false } }
        do {
            async let nights = loadNights(device)
            async let days = loadDays(device)
            let (n, d) = try await (nights, days)
            try Task.checkCancellation()
            let preparation = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                return PerformanceTrace.measure("Trend preparation") { TrendSnapshot(nights: n, days: d, now: now, calendar: calendar) }
            }
            let prepared = try await withTaskCancellationHandler { try await preparation.value } onCancel: { preparation.cancel() }
            guard !Task.isCancelled, requestID == request, scope == source, isCurrent() else { return }
            snapshot = prepared; error = nil
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, requestID == request, scope == source, isCurrent() else { return }
            self.error = error.localizedDescription
        }
    }
}
