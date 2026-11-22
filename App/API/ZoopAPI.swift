import ZoopData
import Foundation
import ZoopTransport

/// Read side of the snoop-api server: nights, days, minutes, sessions, steps and the
/// body profile. Every call is one request helper plus a decodable type.
enum ZoopAPI {
    struct Processing: Decodable, Sendable {
        let pendingDecode: Int
        let decodeFailures: Int
        let pendingAnalysis: Int
        let failedAnalysis: Int
        let oldestPendingDay: String?
        let lastAnalyzedAt: Date?
        let workersHealthy: Bool
        let paused: Bool
    }

    static func processing(deviceId: String) async throws -> Processing {
        try await get("v1/devices/\(deviceId)/processing")
    }

    struct Night: Decodable, Identifiable, Sendable {
        struct Window: Decodable, Sendable {
            let onset: Date
            let offset: Date
            let timeInBedS: Int
            let asleepS: Int
            let wasoS: Int
            let efficiency: Double
            let coverageS: Int
            let disturbances: Int
        }

        struct Physiology: Decodable, Sendable {
            let restingHr: Double?
            let hrvRmssdMs: Double?
            let hrvWindows: Int
            let respiratoryRate: Double?
            let skinTempC: Double?
            let spo2Pct: Double?
            let spo2Windows: Int
        }

        struct StageSummary: Decodable, Sendable {
            let wakeS: Int
            let lightS: Int
            let deepS: Int
            let remS: Int
            let sleepLatencyS: Int
            let remLatencyS: Int?
            let epochs: Int
            let epochsWithCardiac: Int
        }

        struct Metrics: Decodable, Sendable {
            let window: Window
            let physiology: Physiology
            let stages: StageSummary?
            let naps: [Window]
        }

        enum Stage: String, Decodable, Sendable {
            case wake, light, deep, rem
        }

        struct Segment: Decodable, Sendable {
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

    struct Day: Decodable, Identifiable, Sendable {
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
        /// Day load on the 0–21 scale, once the server has analysed the day.
        let load: Double?
        let trimp: Double?
        /// Calories over the day's sessions.
        let kcal: Double?
        /// Minutes in each of the five heart-rate zones.
        let zonesMin: [Int]?
        var id: String { day }
    }

    struct Minute: Decodable, Identifiable, Sendable {
        let ts: Date
        let hr: Int?
        let hrMin: Int?
        let hrMax: Int?
        let skinTempC: Double?
        let steps: Int?
        let bandState: Int?
        let activity: Int?
        let spo2Pct: Int?
        var id: Date { ts }
    }

    struct Epoch: Decodable, Identifiable, Sendable {
        let start: Date
        let hr: Double?
        let hrVariability: Double?
        let rmssd: Double?
        let respRate: Double?
        let moveFrac: Double
        let strapAwake: Bool
        var id: Date { start }
    }

    /// A detected session. `kind` is the user's label when one exists, otherwise the
    /// detector's `detectedKind`.
    struct Workout: Decodable, Identifiable, Hashable, Sendable {
        let id: Int64
        let startTs: Date
        let endTs: Date
        let durationS: Int
        let kind: String
        let detectedKind: String
        let edited: Bool
        let load: Double?
        let avgHr: Double?
        let maxHr: Int?
        let trimp: Double?
        let zonesMin: [Int]?
        let kcal: Double?
        let steps: Int?
        let autoDetected: Bool
        let notificationEligible: Bool?
        let revision: Int64?
        let status: String?
        let lastEdit: String?
        let replacements: [Int64]?
        let metricsPending: Bool?
        let coverageS: Int?
        let hrCoverageS: Int?
        let timezone: String?

        var isActive: Bool { status == nil || status == "active" }
        var isPartial: Bool { coverageS.map { $0 < durationS - 60 } == true || hrCoverageS.map { $0 < durationS - 60 } == true }

    }

    /// Steps through one local day.
    struct StepsDay: Decodable, Sendable {
        struct Bout: Decodable, Identifiable, Sendable {
            let start: Date
            let end: Date
            let durationS: Int
            let steps: Int
            let cadenceSpm: Double
            var id: Date { start }
        }

        let day: String
        /// Counter increments per local hour, 0–23.
        let hours: [Int]
        /// The same, restricted to seconds the strap labelled walking.
        let walkingHours: [Int]
        let total: Int
        let walking: Int
        let bouts: [Bout]
    }

    /// Body profile for calories and zones, and the home time zone days are cut in.
    struct Profile: Codable, Sendable {
        var sex: String?
        var birthYear: Int?
        var weightKg: Double?
        var heightCm: Double?
        var tz: String
        var weightMeasuredAt: Date? = nil
        var weightSource: String? = nil
        var weightSourceName: String? = nil

        static var empty: Profile { Profile(sex: nil, birthYear: nil, weightKg: nil, heightCm: nil, tz: TimeZone.current.identifier) }
    }

    private struct ErrorResponse: Decodable, Sendable {
        struct Detail: Decodable, Sendable { let message: String }
        let error: Detail
    }

    enum Failure: Error, LocalizedError {
        case notConfigured
        case http(Int)
        case server(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Server not configured"
            case let .http(code): "Unable to reach the server (\(code)). Try again."
            case let .server(_, message): message
            }
        }
    }

    // MARK: - Calls

    /// Thirty-second epochs of an analysed night, aligned with its stages.
    static func epochs(deviceId: String, nightOf: String) async throws -> [Epoch] {
        try await get("v1/devices/\(deviceId)/sleeps/\(nightOf)/epochs")
    }

    /// Minute buckets for one local calendar day.
    static func minutes(deviceId: String, day: Date) async throws -> [Minute] {
        try await get("v1/devices/\(deviceId)/days/\(dayString(day))", query: ["tz": TimeZone.current.identifier], maxAge: 10)
    }

    static func days(deviceId: String, limit: Int = 14) async throws -> [Day] {
        try await get("v1/devices/\(deviceId)/days", query: ["limit": String(limit), "tz": TimeZone.current.identifier], maxAge: 10)
    }

    static func nights(deviceId: String, limit: Int = 14, summary: Bool = false) async throws -> [Night] {
        try await get("v1/devices/\(deviceId)/sleeps", query: ["limit": String(limit), "summary": String(summary)], maxAge: 10)
    }

    /// Detected sessions, newest first.
    static func workouts(deviceId: String, limit: Int = 60, from: Date? = nil, to: Date? = nil, status: String = "active") async throws -> [Workout] {
        var query = ["limit": String(limit), "status": status]
        if let from { query["from"] = from.ISO8601Format() }
        if let to { query["to"] = to.ISO8601Format() }
        return try await get("v1/devices/\(deviceId)/workouts", query: query)
    }

    static func workout(deviceId: String, id: Int64) async throws -> Workout {
        try await get("v1/devices/\(deviceId)/workouts/\(id)")
    }

    static func correctWorkout(deviceId: String, command: WorkoutCorrection) async throws -> WorkoutCorrection.Receipt {
        try await send("v1/devices/\(deviceId)/workouts/corrections", method: "POST", body: command)
    }

    /// Calendar arithmetic covers midnight and daylight-saving changes.
    static func minutes(deviceId: String, window: ClosedRange<Date>) async throws -> [Minute] {
        var day = Calendar.current.startOfDay(for: window.lowerBound)
        var result: [Date: Minute] = [:]
        while day <= window.upperBound {
            for minute in try await minutes(deviceId: deviceId, day: day) where window.contains(minute.ts) {
                result[minute.ts] = minute
            }
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return result.values.sorted { $0.ts < $1.ts }
    }

    /// Relabels a session and returns it updated.
    static func setWorkoutKind(deviceId: String, id: Int64, kind: String) async throws -> Workout {
        try await send("v1/devices/\(deviceId)/workouts/\(id)/kind", method: "PUT", body: ["kind": kind])
    }

    /// Hourly steps and walking bouts for one local day.
    static func steps(deviceId: String, day: Date) async throws -> StepsDay {
        try await get("v1/devices/\(deviceId)/days/\(dayString(day))/steps", query: ["tz": TimeZone.current.identifier], maxAge: 10)
    }

    /// The body profile, or nil when none has been entered yet.
    static func profile(deviceId: String) async throws -> Profile? {
        try await get("v1/devices/\(deviceId)/profile")
    }

    static func sleepGoal(deviceId: String) async throws -> SleepGoalStore.Response {
        try await get("v1/devices/\(deviceId)/sleep-goal")
    }

    static func saveSleepGoal(deviceId: String, minutes: Int, initializeOnly: Bool) async throws -> SleepGoalStore.Response {
        struct Body: Encodable { let minutes: Int; let initializeOnly: Bool; let tz: String }
        return try await send("v1/devices/\(deviceId)/sleep-goal", method: "PUT",
                              body: Body(minutes: minutes, initializeOnly: initializeOnly, tz: TimeZone.current.identifier))
    }

    static func saveProfile(deviceId: String, _ profile: Profile) async throws -> Profile {
        try await send("v1/devices/\(deviceId)/profile", method: "PUT", body: profile)
    }

    // MARK: - Plumbing

    static func get<T: Decodable>(_ path: String, query: [String: String] = [:], maxAge: TimeInterval = 0) async throws -> T {
        try await perform(request(path, query: query), maxAge: maxAge)
    }

    static func send<T: Decodable, B: Encodable>(_ path: String, method: String, body: B) async throws -> T {
        var request = try request(path)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)
        await reads.invalidate(cancelInFlight: false)
        do {
            let value: T = try await perform(request)
            await reads.invalidate(cancelInFlight: false)
            return value
        } catch {
            await reads.invalidate(cancelInFlight: false)
            throw error
        }
    }

    static func request(_ path: String, query: [String: String] = [:]) throws -> URLRequest {
        guard let base = Settings.serverURL, !Settings.ingestToken.isEmpty else { throw Failure.notConfigured }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(Settings.ingestToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static let reads = ReadClient()
    static func invalidateReads() async { await reads.invalidate(cancelInFlight: false) }

    private static func perform<T: Decodable>(_ request: URLRequest, maxAge: TimeInterval = 0) async throws -> T {
        let data: Data
        let response: URLResponse
        if request.httpMethod == nil || request.httpMethod == "GET" {
            let result = try await reads.data(for: request, maxAge: maxAge)
            data = result.data; response = result.response
        } else {
            (data, response) = try await ServerSession.shared.data(for: request)
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let body = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw Failure.server(status, body.error.message)
            }
            throw Failure.http(status)
        }
        return try PerformanceTrace.measure("API decode") { try APIDateCoding.decoder().decode(T.self, from: data) }
    }

    private static func dayString(_ day: Date) -> String { DayKey.string(day) }
}
