import XCTest
@testable import Zoop

@MainActor final class SleepGoalStoreTests: XCTestCase {
    private let a = SleepGoalStore.Scope(device: "strap-a", connection: "account-a")
    private let b = SleepGoalStore.Scope(device: "strap-b", connection: "account-b")
    private func defaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "SleepGoalTests-" + UUID().uuidString)!
        defaults.set(540, forKey: SleepGoal.storageKey)
        return defaults
    }
    func testMigratesLegacyOnceAndHonoursServerOnSubsequentLoads() async {
        var server = SleepGoalStore.Response(minutes: 480, configured: false)
        var writes = 0
        let store = SleepGoalStore(defaults: defaults(), legacyScope: a, fetch: { _ in server }, put: { _, minutes, initialize in
            XCTAssertTrue(initialize); writes += 1
            server = .init(minutes: minutes, configured: true); return server
        })
        await store.load(a)
        XCTAssertEqual(store.value(for: a)?.minutes, 540)
        server = .init(minutes: 420, configured: true)
        await store.load(a)
        XCTAssertEqual(store.value(for: a)?.minutes, 420)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(store.value(for: a)?.progress(asleepSeconds: 8 * 3600), 1)
    }
    func testExistingServerGoalWinsAndLegacyCannotLeakAfterRelaunchIntoAnotherAccount() async {
        let prefs = defaults()
        let first = SleepGoalStore(defaults: prefs, legacyScope: a, fetch: { _ in .init(minutes: 600, configured: true) }, put: { _, _, _ in XCTFail("No overwrite"); return .init(minutes: 540, configured: true) })
        await first.load(a)
        XCTAssertEqual(first.value(for: a)?.minutes, 600)
        let marker = prefs.string(forKey: "sleepGoalMigrationOwner")
        XCTAssertEqual(marker?.count, 64)
        XCTAssertFalse(marker?.contains(a.connection) ?? true)
        let second = SleepGoalStore(defaults: prefs, legacyScope: b, fetch: { _ in .init(minutes: 480, configured: false) }, put: { _, _, _ in XCTFail("No cross-account migration"); return .init(minutes: 540, configured: true) })
        await second.load(b)
        XCTAssertEqual(second.value(for: b)?.minutes, 480)
        XCTAssertNil(first.value(for: b))
    }
    func testFailedMigrationCanRetryAfterRelaunchWithoutPersistingCredentials() async {
        let prefs = defaults()
        let failed = SleepGoalStore(defaults: prefs, legacyScope: a, fetch: { _ in .init(minutes: 480, configured: false) }, put: { _, _, _ in throw URLError(.notConnectedToInternet) })
        await failed.load(a)
        XCTAssertNil(failed.value(for: a)); XCTAssertNotNil(failed.error)
        var writes = 0
        let retry = SleepGoalStore(defaults: prefs, legacyScope: a, fetch: { _ in .init(minutes: 480, configured: false) }, put: { _, minutes, initialize in
            XCTAssertTrue(initialize); writes += 1
            return .init(minutes: minutes, configured: true)
        })
        await retry.load(a)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(retry.value(for: a)?.minutes, 540)
    }

    func testFailedSaveKeepsConfirmedGoalAndRetryWorks() async {
        var fail = true
        let store = SleepGoalStore(defaults: defaults(), legacyScope: a, fetch: { _ in .init(minutes: 480, configured: true) }, put: { _, minutes, initialize in
            XCTAssertFalse(initialize)
            if fail { throw URLError(.notConnectedToInternet) }
            return .init(minutes: minutes, configured: true)
        })
        await store.load(a)
        let failed = await store.save(600, scope: a)
        XCTAssertFalse(failed); XCTAssertNotNil(store.error)
        XCTAssertEqual(store.value(for: a)?.minutes, 480)
        fail = false
        let saved = await store.save(600, scope: a)
        XCTAssertTrue(saved); XCTAssertNil(store.error)
        XCTAssertEqual(store.value(for: a)?.minutes, 600)
    }
    func testOldResponseCannotCrossAccountsAndCancelledMigrationDoesNotWrite() async {
        var writes = 0
        let store = SleepGoalStore(defaults: defaults(), legacyScope: a, fetch: { device in
            if device == "strap-a" { try? await Task.sleep(for: .milliseconds(40)) }
            return .init(minutes: 480, configured: false)
        }, put: { _, _, _ in writes += 1; return .init(minutes: 540, configured: true) })
        let old = Task { await store.load(a) }
        await Task.yield()
        await store.load(b)
        await old.value
        XCTAssertNil(store.value(for: a)); XCTAssertEqual(store.value(for: b)?.minutes, 480)
        XCTAssertEqual(writes, 0)
        let cancelled = Task { await store.load(a) }
        await Task.yield(); cancelled.cancel(); await cancelled.value
        XCTAssertEqual(writes, 0)
    }
}
