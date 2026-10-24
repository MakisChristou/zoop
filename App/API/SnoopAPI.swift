import Foundation

/// Read side of the snoop-api server, used by the Sleep and Trends tabs.
enum SnoopAPI {
    struct Night: Decodable, Identifiable {
        struct Window: Decodable {
            let onset: Date
            let offset: Date
            let timeInBedS: Int
            let asleepS: Int
            let wasoS: Int
            let efficiency: Double
            let coverageS: Int
            let disturbances: Int
        }

        struct Physiology: Decodable {
            let restingHr: Double?
            let hrvRmssdMs: Double?
            let hrvWindows: Int
            let respiratoryRate: Double?
            let skinTempC: Double?
            let spo2Pct: Double?
            let spo2Windows: Int
        }

        struct StageSummary: Decodable {
            let wakeS: Int
            let lightS: Int
            let deepS: Int
            let remS: Int
            let sleepLatencyS: Int
            let remLatencyS: Int?
            let epochs: Int
            let epochsWithCardiac: Int
        }

        struct Metrics: Decodable {
            let window: Window
            let physiology: Physiology
            let stages: StageSummary?
            let naps: [Window]
        }

        enum Stage: String, Decodable {
            case wake, light, deep, rem
        }

        struct Segment: Decodable {
            let stage: Stage
            let start: Date
            let end: Date
        }

        let nightOf: String
        let algoVersion: Int
        let startTs: Date
        let endTs: Date
        let stages: [Segment]
        let metrics: Metrics

        var id: String { "\(nightOf)-\(algoVersion)" }
    }

    struct Day: Decodable, Identifiable {
        let day: String
        let steps: Int?
        let stepsWalking: Int?
        let walkingS: Int?
        let hrMin: Int?
        let hrAvg: Double?
        let hrMax: Int?
        let skinTempAvg: Double?
        let asleepS: Int?
        let samples: Int
        var id: String { day }
    }

    enum Failure: Error, LocalizedError {
        case notConfigured
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Server not configured"
            case let .http(code): "HTTP \(code)"
            }
        }
    }

    static func days(deviceId: String, limit: Int = 14) async throws -> [Day] {
        guard let base = Settings.serverURL, !Settings.ingestToken.isEmpty else { throw Failure.notConfigured }
        var components = URLComponents(url: base.appendingPathComponent("v1/devices/\(deviceId)/days"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "tz", value: TimeZone.current.identifier),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(Settings.ingestToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([Day].self, from: data)
    }

    static func nights(deviceId: String, limit: Int = 14) async throws -> [Night] {
        guard let base = Settings.serverURL, !Settings.ingestToken.isEmpty else { throw Failure.notConfigured }
        var components = URLComponents(url: base.appendingPathComponent("v1/devices/\(deviceId)/sleeps"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(Settings.ingestToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "bad date \(text)")
            }
            return date
        }
        return try decoder.decode([Night].self, from: data)
    }
}
