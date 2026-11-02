import Foundation

/// User-entered backend settings. Stored in UserDefaults; nothing is hard-coded.
enum Settings {
    static let serverURLKey = "serverURL"
    static let ingestTokenKey = "ingestToken"
    static let deviceModelKey = "deviceModel"

    static var serverURL: URL? {
        UserDefaults.standard.string(forKey: serverURLKey).flatMap(URL.init(string:))
    }

    static var ingestToken: String {
        UserDefaults.standard.string(forKey: ingestTokenKey) ?? ""
    }

    /// In-memory scope only. Never log or persist this identity.
    static var connectionID: String { (serverURL?.absoluteString ?? "") + "|" + ingestToken }

    static var isConfigured: Bool {
        serverURL != nil && !ingestToken.isEmpty
    }
}
