import XCTest
@testable import ZoopHealth

final class RenameCompatibilityTests: XCTestCase {
    func testLegacyWeightKeepsIdentityAndDisplaysNewBrand() {
        let legacy = WeightReading(id: "snoop:existing", kg: 70, source: "snoop", sourceName: "Snoop")
        XCTAssertEqual(legacy.displaySourceName, "Zoop")
        XCTAssertEqual(legacy.id, "snoop:existing")
        XCTAssertEqual(legacy.sourceName, "Snoop")
        let external = WeightReading(kg: 70, source: "health", sourceName: "Other scale")
        XCTAssertEqual(external.displaySourceName, "Other scale")
    }
}
