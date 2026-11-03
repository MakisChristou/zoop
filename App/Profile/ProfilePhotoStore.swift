import CryptoKit
import Foundation
import Observation
import UIKit

@MainActor @Observable final class ProfilePhotoStore {
    struct Scope: Equatable {
        let device: String
        let connection: String
        var valid: Bool { !device.isEmpty && !connection.isEmpty }
        var diskKey: String { SHA256.hash(data: Data((connection + "|" + device).utf8)).map { String(format: "%02x", $0) }.joined() }
    }
    private(set) var image: UIImage?
    private(set) var loading = false
    private(set) var saving = false
    private(set) var error: String?
    @ObservationIgnored private var scope: Scope?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private let disk: ProfilePhotoDisk
    @ObservationIgnored private let remote: (String, String, Data?) async throws -> Data?
    private static let refreshInterval: TimeInterval = 60

    init(disk: ProfilePhotoDisk = ProfilePhotoDisk(), remote: @escaping (String, String, Data?) async throws -> Data? = { try await SnoopAPI.profilePhoto(device: $0, method: $1, jpeg: $2) }) {
        self.disk = disk; self.remote = remote
    }
    func image(for scope: Scope) -> UIImage? { self.scope == scope ? image : nil }
    func load(_ next: Scope, force: Bool = false) async {
        guard next.valid else { reset(next); return }
        if scope != next { reset(next) }
        guard !saving, !loading, force || loadedAt.map({ Date().timeIntervalSince($0) >= Self.refreshInterval }) != false else { return }
        let id = UUID(); requestID = id; loading = true
        defer { if requestID == id { loading = false } }
        let cached = await disk.read(next.diskKey)
        guard requestID == id, scope == next, !Task.isCancelled else { return }
        if image == nil, let cached { image = UIImage(data: cached) }
        do {
            let data = try await remote(next.device, "GET", nil)
            guard requestID == id, scope == next, !Task.isCancelled else { return }
            image = data.flatMap(UIImage.init(data:)); error = nil; loadedAt = Date()
            try? await disk.save(data, key: next.diskKey)
        } catch {
            guard requestID == id, scope == next, !Task.isCancelled else { return }
            self.error = "Couldn’t load your profile photo. Try again."
        }
    }
    func save(_ jpeg: Data?, for next: Scope) async throws {
        guard next.valid, !saving else { throw Failure.unavailable }
        if scope != next { reset(next) }
        let id = UUID(); requestID = id; saving = true; loading = false; error = nil
        defer { if requestID == id { saving = false } }
        do {
            let data = try await remote(next.device, jpeg == nil ? "DELETE" : "PUT", jpeg)
            guard scope == next, requestID == id, !Task.isCancelled else { throw CancellationError() }
            image = data.flatMap(UIImage.init(data:)); loadedAt = Date()
            try? await disk.save(data, key: next.diskKey)
        } catch {
            if scope == next, requestID == id { self.error = "Couldn’t save your photo. Try again." }
            throw error
        }
    }
    private func reset(_ next: Scope) {
        scope = next; requestID = UUID(); image = nil; loadedAt = nil
        error = nil; loading = false; saving = false
    }
    enum Failure: Error { case unavailable }
}
