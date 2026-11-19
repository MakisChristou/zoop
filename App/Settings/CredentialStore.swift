import Foundation
import Security

struct ServerCredential: Codable, Equatable {
    let server: String
    let token: String
    var accountID: Int64?
    var email: String?
    var devices: [String]?
}

protocol CredentialVault {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func delete() throws
}

struct KeychainVault: CredentialVault {
    let service: String
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "server-credential"]
    }
    func read() throws -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure(status: status) }
        return data
    }
    func write(_ data: Data) throws {
        let values: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(values, uniquingKeysWith: { _, new in new }) as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Couldn’t access saved sign-in. Unlock your iPhone and try again." }
    }
}

/// Serializes migration and replacement; failures never discard the original credential.
final class CredentialStore: @unchecked Sendable {
    private let lock = NSLock()
    private let vault: any CredentialVault
    private let defaults: UserDefaults
    private var cached: ServerCredential?
    private var loaded = false
    init(vault: any CredentialVault, defaults: UserDefaults) {
        self.vault = vault; self.defaults = defaults
    }
    func read() throws -> ServerCredential? {
        let result: (ServerCredential?, Bool) = try lock.withLock {
            if loaded { return (cached, false) }
            if let data = try vault.read() {
                cached = try JSONDecoder().decode(ServerCredential.self, from: data)
            } else if let token = defaults.string(forKey: "ingestToken"), !token.isEmpty,
                      let server = defaults.string(forKey: "serverURL"), !server.isEmpty {
                let credential = ServerCredential(server: server, token: token)
                try vault.write(JSONEncoder().encode(credential))
                cached = credential
            }
            loaded = true
            return (cached, cached != nil)
        }
        // Defaults notifications may synchronously read Settings again. Never hold
        // the credential lock while posting them, including during migration.
        if result.1 { defaults.removeObject(forKey: "ingestToken") }
        return result.0
    }
    func save(_ credential: ServerCredential) throws {
        try lock.withLock {
            try vault.write(JSONEncoder().encode(credential))
            cached = credential; loaded = true
        }
        defaults.removeObject(forKey: "ingestToken")
        defaults.set(credential.server, forKey: "serverURL")
    }
    func clear() throws {
        try lock.withLock {
            try vault.delete()
            cached = nil; loaded = true
        }
        defaults.removeObject(forKey: "ingestToken")
    }
}
