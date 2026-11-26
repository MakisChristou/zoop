import Foundation
import CryptoKit

enum Settings {
    static let serverURLKey = "serverURL"
    static let deviceModelKey = "deviceModel"
    private static let credentials = CredentialStore(
        vault: KeychainVault(service: (Bundle.main.bundleIdentifier ?? "zoop") + ".credentials"),
        defaults: .standard)

    static var credential: ServerCredential? {
        #if targetEnvironment(simulator)
        // Synthetic UI fixtures only. A device build never reads credentials from launch arguments.
        if UserDefaults.standard.string(forKey: "demoSerial") != nil,
           let token = UserDefaults.standard.string(forKey: "ingestToken"),
           let server = UserDefaults.standard.string(forKey: serverURLKey) {
            return ServerCredential(server: server, token: token)
        }
        #endif
        return try? credentials.read()
    }
    static var serverURL: URL? { credential.flatMap { URL(string: $0.server) } }
    static var ingestToken: String { credential?.token ?? "" }
    /// In-memory request identity. Never log or persist it.
    static var connectionID: String { (serverURL?.absoluteString ?? "") + "|" + ingestToken }
    static func permitsDevice(_ serial: String) -> Bool {
        guard let credential else { return false }
        return credential.devices?.contains(serial) ?? true
    }
    /// Browsing uses an explicitly owned device; recording always uses the physical strap.
    static func dataDevice(physicalSerial: String, credential: ServerCredential?) -> String {
        guard let credential else { return "" }
        if !physicalSerial.isEmpty {
            return credential.devices?.contains(physicalSerial) == false ? "" : physicalSerial
        }
        guard let devices = credential.devices, devices.count == 1 else { return "" }
        return devices[0]
    }
    static var isConfigured: Bool { credential != nil }
    static func save(_ credential: ServerCredential) throws {
        try credentials.save(credential)
        WidgetSnapshot.clear()
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
    }
    static func clear() throws {
        try credentials.clear()
        WidgetSnapshot.clear()
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
    }
    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func healthScope(device: String, credential: ServerCredential? = Settings.credential) -> String {
        guard let credential else { return "" }
        guard let account = credential.accountID else { return hash(credential.server + "|" + credential.token + "|" + device) }
        let scope = hash(credential.server + "|account:" + String(account) + "|" + device)
        return UserDefaults.standard.string(forKey: "health.scopeAlias." + scope) ?? scope
    }
    /// The caller must verify the old token belongs to the newly authenticated account first.
    static func preserveHealthScopes(from old: ServerCredential, to new: ServerCredential, devices: [String]) {
        guard old.server.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == new.server.trimmingCharacters(in: CharacterSet(charactersIn: "/")), let account = new.accountID else { return }
        for device in devices {
            let scope = hash(new.server + "|account:" + String(account) + "|" + device)
            UserDefaults.standard.set(healthScope(device: device, credential: old), forKey: "health.scopeAlias." + scope)
        }
    }
}
