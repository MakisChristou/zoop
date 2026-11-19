import Foundation

/// Ships queued frames to snoop-api in batches. Rows leave the queue only after a matching stored or duplicate receipt.
public actor Uploader {
    public struct Stats: Equatable, Sendable {
        public var accepted = 0
        public var duplicates = 0
        public var rejected = 0
        public var lastError: String?
        public var lastSuccess: Date?
        public init() {}
    }

    private struct FrameUpload: Encodable {
        let uploadId: String?
        let clientSeq: Int64
        let channel: Int
        let receivedAt: Date
        let bytes: String

        enum CodingKeys: String, CodingKey {
            case clientSeq = "client_seq", channel, receivedAt = "received_at", bytes, uploadId = "upload_id"
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

    private struct Receipt: Decodable {
        let clientSeq: Int64
        let uploadId: String?
        let status: Status
        let reason: String?
        enum Status: String, Decodable { case stored, duplicate, conflict, rejected }
        enum CodingKeys: String, CodingKey { case clientSeq = "client_seq", uploadId = "upload_id", status, reason }
    }
    private struct IngestResponse: Decodable { let results: [Receipt] }
    private enum ReceiptError: Error, LocalizedError {
        case incomplete
        var errorDescription: String? { "The server did not acknowledge every frame. The batch is saved for retry." }
    }

    public static let batchSize = 200
    /// A dead or unreachable server must fail fast so the status line recovers.
    public static let requestTimeout: TimeInterval = 20

    private let queue: FrameQueue
    private let session: URLSession
    private(set) var stats = Stats()
    private var inFlight = false

    public init(queue: FrameQueue, session: URLSession = .shared) {
        self.queue = queue
        self.session = session
    }

    /// Uploads until the queue is empty or a request fails. Safe to call often.
    public func flush(deviceId: String, model: String, firmware: String?, baseURL: URL, token: String) async -> Stats {
        guard !inFlight, !token.isEmpty, !deviceId.isEmpty else {
            return stats
        }
        inFlight = true
        defer { inFlight = false }

        while true {
            let rows: [FrameQueue.Row]
            do { rows = try queue.peek(limit: Self.batchSize, deviceID: deviceId) } catch {
                stats.lastError = "queue: \(error)"
                return stats
            }
            guard !rows.isEmpty else { return stats }

            let body = IngestRequest(
                deviceId: deviceId, model: model, firmware: firmware,
                frames: rows.map { FrameUpload(uploadId: $0.uploadId, clientSeq: $0.clientSeq, channel: $0.channel, receivedAt: $0.receivedAt, bytes: Data($0.bytes).base64EncodedString()) })

            var request = URLRequest(url: baseURL.appendingPathComponent("v2/ingest"))
            request.timeoutInterval = Self.requestTimeout
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
                guard result.results.count == rows.count else { throw ReceiptError.incomplete }
                var receipts: [Int64: Receipt] = [:]
                for receipt in result.results {
                    guard receipts.updateValue(receipt, forKey: receipt.clientSeq) == nil else { throw ReceiptError.incomplete }
                }
                var resolutions: [FrameQueue.Resolution] = []
                for row in rows {
                    guard let receipt = receipts[row.clientSeq], receipt.uploadId == row.uploadId else { throw ReceiptError.incomplete }
                    switch receipt.status {
                    case .stored, .duplicate: resolutions.append(.init(rowId: row.id))
                    case .conflict, .rejected:
                        resolutions.append(.init(rowId: row.id, holdReason: receipt.reason ?? receipt.status.rawValue))
                    }
                }
                try queue.resolve(resolutions)
                stats.accepted += result.results.filter { $0.status == .stored }.count
                stats.duplicates += result.results.filter { $0.status == .duplicate }.count
                stats.rejected += result.results.filter { $0.status == .rejected || $0.status == .conflict }.count
                stats.lastSuccess = Date()
                stats.lastError = nil
            } catch {
                stats.lastError = error.localizedDescription
                return stats
            }
        }
    }
}
