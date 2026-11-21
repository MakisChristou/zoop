import XCTest
@testable import Zoop

final class AccountErasureTests: XCTestCase {
    func testReceiptContainsOnlyCleanupIdentifiersAndSurvivesEncoding() throws {
        let receipt = AccountErasure(account: 12, devices: ["SYNTHETIC"], scopes: ["scope"], photoKeys: ["photo"])
        let data = try JSONEncoder().encode(receipt)
        let decoded = try JSONDecoder().decode(AccountErasure.self, from: data)
        XCTAssertEqual(decoded.devices, ["SYNTHETIC"])
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["account", "devices", "scopes", "photoKeys"])
    }
    func testBackupExclusionPreservesExistingRecordingsAndPreferences() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let support = folder.appendingPathComponent("Application Support")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let recording = support.appendingPathComponent("recording")
        try Data([1,2,3]).write(to: recording)
        try DeviceDataProtection.prepare(library: folder)
        XCTAssertEqual(try Data(contentsOf: recording), Data([1,2,3]))
        for path in [folder, support, folder.appendingPathComponent("Preferences")] {
            XCTAssertEqual(try path.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        }
    }
}
