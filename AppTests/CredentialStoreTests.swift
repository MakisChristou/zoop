import XCTest
@testable import Zoop

final class CredentialStoreTests: XCTestCase {
    final class Vault: CredentialVault {
        var data: Data?
        var failing = false
        func read() throws -> Data? { if failing { throw CocoaError(.fileReadNoPermission) }; return data }
        func write(_ data: Data) throws { if failing { throw CocoaError(.fileWriteNoPermission) }; self.data = data }
        func delete() throws { if failing { throw CocoaError(.fileWriteNoPermission) }; data = nil }
    }
    final class ReentrantDefaults: UserDefaults, @unchecked Sendable {
        var onRemoval: (() -> Void)?
        override func removeObject(forKey defaultName: String) {
            super.removeObject(forKey: defaultName)
            onRemoval?()
        }
    }
    func testSettingsObserverCanReadCredentialsDuringSaveAndClear() throws {
        let name = "credential-test-" + UUID().uuidString
        let defaults = ReentrantDefaults(suiteName: name)!
        defer { defaults.onRemoval = nil; defaults.removePersistentDomain(forName: name) }
        let store = CredentialStore(vault: Vault(), defaults: defaults)
        var observed: [ServerCredential?] = []
        defaults.onRemoval = { observed.append(try? store.read()) }
        let credential = ServerCredential(server: "https://server.example", token: "test")
        try store.save(credential)
        try store.clear()
        XCTAssertEqual(observed, [credential, nil])
    }
    func testMigrationSurvivesFailedKeychainAccessAndPreservesExactCredential() throws {
        let name = "credential-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("https://server.example", forKey: "serverURL")
        defaults.set("legacy-test-token", forKey: "ingestToken")
        let vault = Vault(); vault.failing = true
        let store = CredentialStore(vault: vault, defaults: defaults)
        XCTAssertThrowsError(try store.read())
        XCTAssertEqual(defaults.string(forKey: "ingestToken"), "legacy-test-token")
        vault.failing = false
        let saved = try XCTUnwrap(store.read())
        XCTAssertEqual(saved.token, "legacy-test-token")
        XCTAssertNil(defaults.string(forKey: "ingestToken"))
        XCTAssertEqual(try CredentialStore(vault: vault, defaults: defaults).read(), saved)
        vault.failing = true
        XCTAssertThrowsError(try store.clear())
        XCTAssertEqual(try store.read(), saved)
        vault.failing = false
        try store.clear()
        XCTAssertNil(try store.read())
        XCTAssertNil(try CredentialStore(vault: vault, defaults: defaults).read())
    }
    func testFailedReplacementKeepsPriorAccount() throws {
        let name = "credential-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let vault = Vault(); let store = CredentialStore(vault: vault, defaults: defaults)
        let first = ServerCredential(server: "https://one.example", token: "first", accountID: 1)
        try store.save(first)
        vault.failing = true
        XCTAssertThrowsError(try store.save(ServerCredential(server: "https://two.example", token: "second", accountID: 2)))
        XCTAssertEqual(try store.read(), first)
    }
    func testHealthScopeSurvivesTokenRotationButSeparatesServersAndAccounts() {
        let prefix = "https://scope-test-" + UUID().uuidString + ".example"
        let first = ServerCredential(server: prefix, token: "old", accountID: 1)
        let rotated = ServerCredential(server: prefix, token: "new", accountID: 1)
        XCTAssertEqual(Settings.healthScope(device: "A", credential: first), Settings.healthScope(device: "A", credential: rotated))
        XCTAssertNotEqual(Settings.healthScope(device: "A", credential: first), Settings.healthScope(device: "B", credential: first))
        XCTAssertNotEqual(Settings.healthScope(device: "A", credential: first), Settings.healthScope(device: "A", credential: .init(server: prefix, token: "old", accountID: 2)))
        XCTAssertNotEqual(Settings.healthScope(device: "A", credential: first), Settings.healthScope(device: "A", credential: .init(server: "https://other.example", token: "old", accountID: 1)))
        let legacy = ServerCredential(server: prefix, token: "legacy")
        let key = "health.scopeAlias." + Settings.hash(prefix + "|account:1|A")
        defer { UserDefaults.standard.removeObject(forKey: key) }
        Settings.preserveHealthScopes(from: legacy, to: first, devices: ["A"])
        XCTAssertEqual(Settings.healthScope(device: "A", credential: first), Settings.healthScope(device: "A", credential: legacy))
        XCTAssertEqual(Settings.healthScope(device: "A", credential: rotated), Settings.healthScope(device: "A", credential: legacy))
    }
    func testLoginRejectsUnsafeOrAmbiguousServerURLs() throws {
        for url in ["https://user:password@example.test", "https://example.test/path", "https://example.test?x=1", "file:///tmp/a", "https://example.test#fragment"] {
            XCTAssertThrowsError(try ServerSignIn.address(url), url)
        }
        XCTAssertNoThrow(try ServerSignIn.address("https://server.example"))
        for url in ["http://127.0.0.1:18471", "http://192.168.1.10:8080", "http://zoop.local:8080", "http://[fd00::1]:8080", "http://server.example:8080"] {
            XCTAssertNoThrow(try ServerSignIn.address(url))
        }
    }
}
