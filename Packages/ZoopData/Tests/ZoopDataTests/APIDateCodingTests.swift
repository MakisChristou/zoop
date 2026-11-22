import Foundation
import XCTest
@testable import ZoopData

final class APIDateCodingTests: XCTestCase {
    func testWholeFractionalAndOffsetTimestampsAgree() throws {
        let data = Data("""
        ["2026-11-22T12:00:00Z", "2026-11-22T12:00:00.000000Z", "2026-11-22T14:00:00+02:00"]
        """.utf8)
        let dates = try APIDateCoding.decoder().decode([Date].self, from: data)
        XCTAssertEqual(Set(dates).count, 1)
        XCTAssertThrowsError(try APIDateCoding.decoder().decode(Date.self, from: Data("\"not a timestamp\"".utf8)))
    }
    func testFractionalPrecisionSurvivesConcurrentDecodes() async throws {
        try await withThrowingTaskGroup(of: Date.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    try APIDateCoding.decoder().decode(Date.self, from: Data("\"2026-11-22T12:00:00.125Z\"".utf8))
                }
            }
            for try await date in group {
                XCTAssertEqual(date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1), 0.125, accuracy: 0.001)
            }
        }
    }
}
