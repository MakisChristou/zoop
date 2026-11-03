import Foundation

/// Local session files are independent of the raw upload queue. Writes are atomic.
public actor ECGJournal {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }

    private func write<T: Encodable>(_ value: T, to name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        let data = try JSONEncoder().encode(value)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
    public func pending() throws -> [ECGCleanup] {
        let url = directory.appendingPathComponent("cleanup.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ECGCleanup].self, from: Data(contentsOf: url))
    }
    public func setPending(_ item: ECGCleanup) throws {
        var values = try pending().filter { $0.device != item.device }
        if !item.isEmpty { values.append(item) }
        try write(values, to: "cleanup.json")
    }
    public func save(_ recording: ECGRecording) throws {
        try write(recording, to: "\(recording.id.uuidString).ecg.json")
    }
    public func writeAttemptStatus(_ status: ECGAttemptStatus) throws {
        try write(status, to: "latest-attempt.json")
    }
    public func recording(id: UUID) throws -> ECGRecording {
        try JSONDecoder().decode(ECGRecording.self, from: Data(contentsOf: directory.appendingPathComponent("\(id.uuidString).ecg.json")))
    }
    public func summaries(device: String) throws -> [ECGRecordingSummary] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try files.filter { $0.lastPathComponent.hasSuffix(".ecg.json") }.map {
            try JSONDecoder().decode(ECGRecording.self, from: Data(contentsOf: $0)).summary
        }.filter { $0.device == device }.sorted { $0.startedAt > $1.startedAt }
    }
}
