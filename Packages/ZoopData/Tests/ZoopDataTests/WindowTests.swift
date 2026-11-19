import XCTest
@testable import ZoopData
final class WindowTests: XCTestCase {
    func testWindowMatchesFilteringAndKeepsLineNeighbours() {
        let values = (0..<10000).map { Double($0) * 0.3 }
        for start in stride(from: -100.0, to: 3100, by: 37) {
            let bounds = SortedWindow.range(values, from: start, to: start + 7, key: { $0 })
            XCTAssertEqual(Array(values[bounds]), values.filter { $0 >= start && $0 < start + 7 })
            let padded = SortedWindow.range(values, from: start, to: start + 7, padding: 1, key: { $0 })
            XCTAssertLessThanOrEqual(padded.count, bounds.count + 2)
        }
        XCTAssertEqual(SortedWindow.lowerBound([1.0,2,2,3], value: 2, key: { $0 }),1)
        XCTAssertEqual(SortedWindow.range([Double](),from:0,to:1,key:{$0}),0..<0)
    }
}
