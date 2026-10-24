import Foundation

/// Ships queued frames to snoop-api in batches. Rows leave the queue only after a 2xx.
actor Uploader {
    struct Stats: Equatable {
        var accepted = 0
        var duplicates = 0
        var rejected = 0
        var lastError: String?
        var lastSuccess: Date?
    }

    private struct FrameUpload: Encodable {
        let clientSeq: Int64
        let channel: Int
        let receivedAt: Date
        let bytes: String

        enum CodingKeys: String, CodingKey {
            case clientSeq = "client_seq", channel, receivedAt = "received_at", bytes
        }
    }

    private struct IngestRequest: Encodable {
        let deviceId: String
        let model: String
        let firmware: String?
        let frames: [FrameUpload]

        enum CodingKeys: String, CodingKey {
            case deviceId = "device_id", model, firmware, frames
        }
    }

    private struct IngestResponse: Decodable {
        let accepted: Int
        let duplicates: Int
        let rejected: Int
    }

    static let batchSize = 200
    /// A dead or unreachable server must fail fast so the status line recovers.
    static let requestTimeout: TimeInterval = 20

    private let queue: FrameQueue
    private let session: URLSession
    private(set) var stats = Stats()
    private var inFlight = false

    init(queue: FrameQueue, session: URLSession = .shared) {
        self.queue = queue
        self.session = session
    }

    /// Uploads until the queue is empty or a request fails. Safe to call often.
    func flush(deviceId: String, model: String, firmware: String?) async -> Stats {
        guard !inFlight, let baseURL = Settings.serverURL, !Settings.ingestToken.isEmpty, !deviceId.isEmpty else {
            return stats
        }
        inFlight = true
        defer { inFlight = false }

        while true {
            let rows: [FrameQueue.Row]
            do { rows = try queue.peek(limit: Self.batchSize) } catch {
                stats.lastError = "queue: \(error)"
                return stats
            }
            guard !rows.isEmpty else { return stats }

            let body = IngestRequest(
                deviceId: deviceId, model: model, firmware: firmware,
                frames: rows.map { FrameUpload(clientSeq: $0.clientSeq, channel: $0.channel, receivedAt: $0.receivedAt, bytes: Data($0.bytes).base64EncodedString()) })

            var request = URLRequest(url: baseURL.appendingPathComponent("v1/ingest"))
            request.timeoutInterval = Self.requestTimeout
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(Settings.ingestToken)", forHTTPHeaderField: "Authorization")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            do {
                request.httpBody = try encoder.encode(body)
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    stats.lastError = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                    return stats
                }
                let result = try JSONDecoder().decode(IngestResponse.self, from: data)
                stats.accepted += result.accepted
                stats.duplicates += result.duplicates
                stats.rejected += result.rejected
                stats.lastSuccess = Date()
                stats.lastError = nil
                try queue.remove(ids: rows.map(\.id))
            } catch {
                stats.lastError = error.localizedDescription
                return stats
            }
        }
    }
}
