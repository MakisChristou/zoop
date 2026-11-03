import Foundation

actor ProfilePhotoDisk {
    private let folder: URL
    init(folder: URL = URL.cachesDirectory.appendingPathComponent("ProfilePhotos", isDirectory: true)) { self.folder = folder }
    func read(_ key: String) -> Data? { try? Data(contentsOf: file(key)) }
    func save(_ data: Data?, key: String) throws {
        let url = file(key)
        if let data {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
    private func file(_ key: String) -> URL { folder.appendingPathComponent(key).appendingPathExtension("jpg") }
}
