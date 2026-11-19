import Foundation
import XCTest
@testable import ZoopHealth

final class HistoryConsentTests: XCTestCase {
    private let old = Date(timeIntervalSince1970: 1_700_000_000)
    private var range: HealthJournal.Range { .init(from: old.addingTimeInterval(-100), to: old.addingTimeInterval(100)) }
    private var record: HealthRecord {
        .init(id: "sleep:old", domain: "sleep", version: 1, sequence: 1, startTs: old.addingTimeInterval(-60), endTs: old, payload: .init(kind: "main", intervals: [], count: nil, kg: nil), removed: false)
    }
    func testWeightImportDoesNotEnrolExportsOrResetExportCursor() throws {
        var journal = HealthJournal(); journal.connectedAt = old.addingTimeInterval(1000)
        journal.cursor = 23; journal.pageCursor = 7; journal.watermark = 30; journal.snapshot = false; journal.paused = true
        journal.approveWeightImport(range)
        let restored = try JSONDecoder().decode(HealthJournal.self, from: JSONEncoder().encode(journal))
        XCTAssertTrue(restored.permitsWeightImport(at: old)); XCTAssertFalse(restored.eligible(record))
        XCTAssertEqual(restored.cursor, 23); XCTAssertEqual(restored.pageCursor, 7); XCTAssertEqual(restored.watermark, 30)
        XCTAssertFalse(restored.snapshot); XCTAssertTrue(restored.paused)
        XCTAssertEqual(restored.pendingWeightImport, range); XCTAssertEqual(restored.importStart, range.from)
    }
    func testExportSelectionDoesNotConsentToWeightImport() {
        var journal = HealthJournal(); journal.connectedAt = old.addingTimeInterval(1000)
        journal.backfill(range)
        XCTAssertTrue(journal.eligible(record)); XCTAssertFalse(journal.permitsWeightImport(at: old))
        XCTAssertNil(journal.importStart); XCTAssertNil(journal.pendingWeightImport)
    }
    func testShippedJournalDecodesWithoutNewFieldsAndRetainsBothLegacyConsents() throws {
        var journal = HealthJournal(); journal.connectedAt = old.addingTimeInterval(1000); journal.ranges = [range]
        journal.weights = [WeightReading(id: "health:old", measuredAt: old, kg: 81, source: "health")]
        journal.anchor = Data([1, 2, 3]); journal.cursor = 21
        // Represents the exact old Codable schema: no newly added keys.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as? [String: Any])
        for key in ["exportRanges", "weightImportRanges", "pendingWeightImport"] { json.removeValue(forKey: key) }
        var restored = try JSONDecoder().decode(HealthJournal.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(restored.eligible(record)); XCTAssertTrue(restored.permitsWeightImport(at: old))
        XCTAssertEqual(restored.weights, journal.weights); XCTAssertEqual(restored.anchor, journal.anchor); XCTAssertEqual(restored.cursor, 21)
        restored.clearExportHistory()
        XCTAssertFalse(restored.eligible(record)); XCTAssertTrue(restored.permitsWeightImport(at: old))
    }
}
