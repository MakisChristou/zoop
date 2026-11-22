import Foundation
import CryptoKit
import Observation

/// Server-owned display preference, isolated by server/account/device. Legacy
/// phone settings initialize an unset target once and never overwrite one.
@MainActor @Observable final class SleepGoalStore {
    struct Scope: Codable, Hashable { let device: String; let connection: String }
    struct Response: Codable, Sendable { let minutes: Int; let configured: Bool }
    private(set) var loading = false
    private(set) var error: String?
    private var scope: Scope?
    private var goal: SleepGoal?
    private var saving = false
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let legacyScope: Scope
    @ObservationIgnored private let fetch: (String) async throws -> Response
    @ObservationIgnored private let put: (String, Int, Bool) async throws -> Response
    private static let migrationKey = "sleepGoalMigrationOwner"

    init(defaults: UserDefaults = .standard, legacyScope: Scope,
         fetch: @escaping (String) async throws -> Response = { try await ZoopAPI.sleepGoal(deviceId: $0) },
         put: @escaping (String, Int, Bool) async throws -> Response = { try await ZoopAPI.saveSleepGoal(deviceId: $0, minutes: $1, initializeOnly: $2) }) {
        self.defaults = defaults; self.legacyScope = legacyScope; self.fetch = fetch; self.put = put
    }

    func value(for scope: Scope) -> SleepGoal? { self.scope == scope ? goal : nil }

    func load(_ scope: Scope, isCurrent: () -> Bool = { true }) async {
        guard isCurrent(), !Task.isCancelled else { return }
        if self.scope == scope, saving { return }
        activate(scope)
        let id = UUID(); request = id
        guard !scope.device.isEmpty, !scope.connection.isEmpty else { return }
        loading = true
        defer { if request == id { loading = false } }
        do {
            let legacy = legacyMinutes(for: scope)
            var result = try await fetch(scope.device)
            guard request == id, isCurrent(), !Task.isCancelled else { return }
            if !result.configured, let legacy {
                result = try await put(scope.device, legacy, true)
            }
            guard request == id, isCurrent(), !Task.isCancelled else { return }
            goal = SleepGoal(minutes: result.minutes); error = nil
        } catch {
            guard request == id, isCurrent(), !Task.isCancelled else { return }
            self.error = "Couldn’t load sleep goal. Try again."
        }
    }

    @discardableResult func save(_ minutes: Int, scope: Scope, isCurrent: () -> Bool = { true }) async -> Bool {
        guard isCurrent(), !Task.isCancelled, !loading, value(for: scope) != nil else { return false }
        let id = UUID(); request = id; loading = true; saving = true
        defer { if request == id { loading = false; saving = false } }
        do {
            let result = try await put(scope.device, minutes, false)
            guard request == id, isCurrent(), !Task.isCancelled else { return false }
            goal = SleepGoal(minutes: result.minutes); error = nil
            return true
        } catch {
            guard request == id, isCurrent(), !Task.isCancelled else { return false }
            self.error = "Couldn’t save sleep goal. Try again."
            return false
        }
    }

    private func activate(_ scope: Scope) {
        if self.scope != scope { goal = nil; error = nil; loading = false; saving = false; self.scope = scope }
    }

    private func legacyMinutes(for scope: Scope) -> Int? {
        guard defaults.object(forKey: SleepGoal.storageKey) != nil else { return nil }
        // connection contains credentials: only a one-way scope fingerprint may persist.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let encoded = try? encoder.encode(scope) else { return nil }
        let owner = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
        if let claimed = defaults.string(forKey: Self.migrationKey) {
            guard claimed == owner else { return nil }
        } else {
            guard scope.connection == legacyScope.connection,
                  legacyScope.device.isEmpty || scope.device == legacyScope.device else { return nil }
            // Claim before sending, so a failed request cannot migrate to another account.
            defaults.set(owner, forKey: Self.migrationKey)
        }
        return SleepGoal(minutes: defaults.integer(forKey: SleepGoal.storageKey)).minutes
    }
}
