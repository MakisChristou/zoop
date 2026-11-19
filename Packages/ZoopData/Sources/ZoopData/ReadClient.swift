import Foundation

/// Bounded, in-memory GET reuse. Each caller owns a cancellation lease. The last
/// cancelled caller cancels transport, and invalidation prevents old data re-entering cache.
public actor ReadClient {
    public struct Response: Sendable {
        public let data: Data
        public let response: HTTPURLResponse
        public init(data: Data, response: HTTPURLResponse) { self.data = data; self.response = response }
    }
    public typealias Transport = @Sendable (URLRequest) async throws -> Response
    private struct Entry { let response: Response; let expires: Date; var used: UInt64 }
    private struct Pending { let id: UUID; let task: Task<Response, Error>; var callers: Set<UUID> }
    private let transport: Transport
    private let capacity: Int
    private let byteLimit: Int
    private var cache: [String: Entry] = [:]
    private var pending: [String: Pending] = [:]
    private var clock: UInt64 = 0
    private var generation = 0

    public init(capacity: Int = 64, byteLimit: Int = 8 * 1024 * 1024, transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return Response(data: data, response: response)
    }) {
        self.capacity = max(0, capacity); self.byteLimit = max(0, byteLimit); self.transport = transport
    }
    public func invalidate(cancelInFlight: Bool = true) {
        generation += 1; cache.removeAll()
        if cancelInFlight { for request in pending.values { request.task.cancel() } }
        pending.removeAll()
    }
    public func data(for request: URLRequest, maxAge: TimeInterval = 0) async throws -> Response {
        try Task.checkCancellation()
        // Credentials are kept in memory only, never logged or persisted.
        let key = (request.url?.absoluteString ?? "") + "|" + (request.value(forHTTPHeaderField: "Authorization") ?? "")
        clock &+= 1
        if maxAge > 0, var entry = cache[key], entry.expires > Date() {
            entry.used = clock; cache[key] = entry; return entry.response
        }
        let caller = UUID(), epoch = generation
        var operation: Pending
        if let existing = pending[key] { operation = existing }
        else {
            let transport = transport
            operation = Pending(id: UUID(), task: Task { try await transport(request) }, callers: [])
        }
        operation.callers.insert(caller); pending[key] = operation
        let id = operation.id, task = operation.task
        return try await withTaskCancellationHandler {
            defer { release(key: key, operation: id, caller: caller) }
            let response = try await task.value
            try Task.checkCancellation()
            guard !task.isCancelled else { throw CancellationError() }
            if generation == epoch, maxAge > 0, (200..<300).contains(response.response.statusCode), response.data.count <= byteLimit {
                cache[key] = Entry(response: response, expires: Date().addingTimeInterval(maxAge), used: clock)
                trim()
            }
            return response
        } onCancel: {
            Task { await self.release(key: key, operation: id, caller: caller) }
        }
    }
    private func release(key: String, operation: UUID, caller: UUID) {
        guard var current = pending[key], current.id == operation else { return }
        current.callers.remove(caller)
        if current.callers.isEmpty { current.task.cancel(); pending.removeValue(forKey: key) }
        else { pending[key] = current }
    }
    private func trim() {
        while cache.count > capacity || cache.values.reduce(0, { $0 + $1.response.data.count }) > byteLimit {
            guard let key = cache.min(by: { $0.value.used < $1.value.used })?.key else { break }
            cache.removeValue(forKey: key)
        }
    }
}
