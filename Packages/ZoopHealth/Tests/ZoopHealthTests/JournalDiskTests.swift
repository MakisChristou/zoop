import XCTest
@testable import ZoopHealth

final class JournalDiskTests: XCTestCase {
    func testOlderSettingsCannotOverwriteNewerReceipt() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = HealthJournalDisk()
        let (file, original) = try await disk.open(folder: folder, name: "test")
        var newest = original
        newest.weights = [WeightReading(id: "snoop:test-weight", kg: 75)]
        newest.weightCursor = 21
        try await disk.save(newest, to: file, revision: 2)
        try await disk.save(original, to: file, revision: 1)
        let reopened = try await disk.open(folder: folder, name: "test").1
        XCTAssertEqual(reopened.weights, newest.weights)
        XCTAssertEqual(reopened.weightCursor, 21)
    }
    func testExistingJournalWithoutCursorOpensWithoutLosingReceipts() throws {
        var journal = HealthJournal()
        journal.versions["sleep:one"] = 3
        journal.weights = [WeightReading(id: "health:existing", kg: 75, source: "health", sourceName: "Other app")]
        let data = try JSONEncoder().encode(journal)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "weightCursor")
        let loaded = try JSONDecoder().decode(HealthJournal.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(loaded.weightCursor)
        XCTAssertEqual(loaded.weights, journal.weights)
        XCTAssertEqual(loaded.versions, journal.versions)
    }
}
