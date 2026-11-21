import Foundation

/// A non-secret receipt resumes local cleanup after an interrupted account deletion.
struct AccountErasure: Codable {
    let account: Int64
    let devices: [String]
    let scopes: [String]
    let photoKeys: [String]
    static let key = "account.erasureReceipt"
    static var pending: AccountErasure? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
    func persist() throws {
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: Self.key)
    }
    static func finish() { UserDefaults.standard.removeObject(forKey: key) }
}
