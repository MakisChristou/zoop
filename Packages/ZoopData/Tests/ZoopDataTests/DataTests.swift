import XCTest
@testable import ZoopData

final class DataTests: XCTestCase {
    func testDayKeysAcrossDSTAndTimeZones() throws {
        for zone in ["UTC", "Europe/Berlin", "America/New_York", "Asia/Kathmandu"] {
            let tz = try XCTUnwrap(TimeZone(identifier: zone))
            for key in ["2024-02-29", "2026-03-29", "2026-10-25", "2026-11-01"] {
                XCTAssertEqual(DayKey.string(try XCTUnwrap(DayKey.date(key, timeZone: tz)), timeZone: tz), key)
            }
        }
        for bad in ["2025-02-29", "2026-13-01", "2026-00-12", "2026-1-01", "bad"] { XCTAssertNil(DayKey.date(bad)) }
    }
    func testTimestampFormatsAndInvalidInput() throws {
        let dates = try APIDateCoding.decoder().decode([Date].self, from: Data("[\"2026-01-01T00:00:00Z\",\"2026-01-01T02:00:00.125+02:00\"]".utf8))
        XCTAssertEqual(dates[1].timeIntervalSince(dates[0]), 0.125, accuracy: 0.00001)
        XCTAssertThrowsError(try APIDateCoding.decoder().decode([Date].self, from: Data("[\"not a date\"]".utf8)))
    }
    func testRollingMeanMatchesOriginalForGapsEqualTimesAndYearOfData() {
        let origin = Date(timeIntervalSince1970: 1_700_000_000)
        var points: [TrendPoint] = []
        for day in 0..<365 where day % 11 != 0 {
            let date = origin.addingTimeInterval(Double(day) * 86400)
            points.append(TrendPoint(date: date, value: Double((day * 17) % 31)))
        }
        points.append(points[10]); points.reverse()
        let actual = TrendSeries(points)
        for (point, result) in zip(actual.points, actual.rolling) {
            let window = points.filter { $0.date <= point.date && $0.date > point.date.addingTimeInterval(-7 * 86400) }
            XCTAssertEqual(result.value, window.map(\.value).reduce(0,+) / Double(window.count), accuracy: 0.000001)
        }
        XCTAssertNil(TrendSeries([]).average)
    }
    func testYearPreparationPerformance() {
        let points = (0..<365).map { TrendPoint(date: Date(timeIntervalSince1970: Double($0*86400)), value: Double($0 % 17)) }
        measure { for _ in 0..<20 { XCTAssertEqual(TrendSeries(points).rolling.count, 365) } }
    }
    func testCompletionIsCalledOnlyOnce() {
        let count = Counter()
        let completion = CompletionOnce { count.increment() }
        DispatchQueue.concurrentPerform(iterations: 100) { _ in completion.call() }
        XCTAssertEqual(count.value, 1)
    }
}
private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}
