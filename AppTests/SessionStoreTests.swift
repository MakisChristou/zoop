import XCTest
import Observation
@testable import Zoop

private struct Record: SessionRecord {
    let id: Int64
    var startTs = Date(timeIntervalSince1970: 100)
    var endTs = Date(timeIntervalSince1970: 200)
    var isActive = true
    var needsMetrics = false
}
private actor Server {
    var slow = false
    var calls = 0
    var listCalls = 0
    func reset() { calls = 0; listCalls = 0; slow = false }
    func list(device: String) async throws -> [Record] {
        listCalls += 1
        let first = listCalls == 1
        if slow && first { try await Task.sleep(for: .milliseconds(100)) }
        return [Record(id: device == "other" ? 3 : first ? 1 : 2)]
    }
    func setSlow() { slow = true }
    func get() -> Record { calls += 1; return Record(id: 2) }
}
private enum Endpoint: SessionEndpoint {
    static let server = Server()
    static let limit = 500, noun = "Workout", refreshMessage = "Reconnect"
    static func list(device: String, from: Date?, to: Date?) async throws -> [Record] { try await server.list(device: device) }
    static func get(device: String, id: Int64) async throws -> Record { await server.get() }
    static func save(device: String, command: WorkoutCorrection) async throws -> WorkoutCorrection.Receipt {
        .init(operationId: command.operationId, workoutIds: [2])
    }
}
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
@MainActor final class SessionStoreTests: XCTestCase {
    func testSlowOldLoadCannotReplaceNewRange() async throws {
        await Endpoint.server.reset(); await Endpoint.server.setSlow()
        let store = SessionStore<Endpoint>()
        let old = Task { try await store.reload(device: "one") }
        try await Task.sleep(for: .milliseconds(20))
        try await store.reload(device: "one")
        try await old.value
        XCTAssertEqual(store.items.map(\.id),[2])
    }
    func testDeviceSwitchFencesOldResponse() async throws {
        await Endpoint.server.reset(); await Endpoint.server.setSlow()
        let store = SessionStore<Endpoint>()
        let old = Task { try await store.reload(device: "one") }
        try await Task.sleep(for: .milliseconds(20))
        try await store.reload(device: "other")
        try await old.value
        XCTAssertEqual(store.items.map(\.id),[3])
    }
    func testCorrectionPollsOnlyAffectedIdentityAndStops() async throws {
        await Endpoint.server.reset()
        let store = SessionStore<Endpoint>()
        try await store.save(device: "one", command: .init(action: "edit"))
        for _ in 0..<100 where store.changeToken < 2 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(store.changeToken,2)
        let lists = await Endpoint.server.listCalls, gets = await Endpoint.server.calls
        XCTAssertEqual(lists,1); XCTAssertEqual(gets,1)
        XCTAssertEqual(store.items.map(\.id),[1,2])
        XCTAssertNil(store.refreshError)
    }
    func testUnrelatedAppChangesDoNotInvalidateTrendDependencies() {
        let model = AppModel(servicesEnabled: false)
        let flag = Flag()
        withObservationTracking {
            _ = model.strap.serial
            _ = model.sleep.changeToken
        } onChange: { flag.set() }
        model.analysisRevision += 1
        model.health.showWeightEntry = true
        XCTAssertFalse(flag.isSet)
    }
}
