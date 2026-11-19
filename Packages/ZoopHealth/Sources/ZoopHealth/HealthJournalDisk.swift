import Foundation
import os

/// Serial disk ownership keeps encoding, atomic replacement and journal recovery
/// off the UI executor. Revisions prevent delayed settings tasks overwriting newer receipts.
public actor HealthJournalDisk {
    private let signposter = OSSignposter(subsystem: "snoop", category: "performance")
    private var revisions: [URL: UInt64] = [:]
    public init() {}
    public func open(folder: URL, name: String) throws -> (URL, HealthJournal) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var folder = folder
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let file = folder.appendingPathComponent(name + ".json")
        let journal = FileManager.default.fileExists(atPath: file.path)
            ? try JSONDecoder().decode(HealthJournal.self, from: Data(contentsOf: file)) : HealthJournal()
        return (file, journal)
    }
    public func save(_ journal: HealthJournal, to file: URL, revision: UInt64) throws {
        guard revision > (revisions[file] ?? 0) else { return }
        let interval = signposter.beginInterval("Health journal save")
        defer { signposter.endInterval("Health journal save", interval) }
        try JSONEncoder().encode(journal).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        revisions[file] = revision
    }
}
