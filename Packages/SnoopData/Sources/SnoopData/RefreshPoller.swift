import Foundation

/// A bounded refresh loop; cancellation and errors belong to the caller's lifecycle.
public enum RefreshPoller {
    @MainActor public static func wait(attempts: Int, delay: Duration, ready: () async throws -> Bool) async throws -> Bool {
        for attempt in 0..<max(0, attempts) {
            try Task.checkCancellation()
            if try await ready() { return true }
            if attempt + 1 < attempts { try await Task.sleep(for: delay) }
        }
        return false
    }
}
