import Foundation

/// Serial persistence barrier shared by data and history-end frames. Completions
/// run in receive order on the main queue, only after each SQLite commit succeeds.
/// A failed write keeps that frame and everything behind it pending for retry.
public final class FrameWriter: @unchecked Sendable {
    private struct Pending {
        let bytes: [UInt8]; let channel: Int; let at: Date; let sourceID: String?; let completion: @MainActor @Sendable () -> Void
    }
    private let worker = DispatchQueue(label: "snoop.frame-writer")
    private let save: @Sendable ([UInt8], Int, Date, String?) throws -> Void
    private let onFailure: @MainActor @Sendable (Error) -> Void
    private let onRecovery: @MainActor @Sendable () -> Void
    private var pending: [Pending] = []
    private var paused = false
    private var head = 0

    public init(save: @escaping @Sendable ([UInt8], Int, Date, String?) throws -> Void,
                onFailure: @escaping @MainActor @Sendable (Error) -> Void, onRecovery: @escaping @MainActor @Sendable () -> Void) {
        self.save = save; self.onFailure = onFailure; self.onRecovery = onRecovery
    }
    public func enqueue(_ bytes: [UInt8], channel: Int, at: Date = Date(), sourceID: String? = nil, completion: @escaping @MainActor @Sendable () -> Void) {
        worker.async {
            self.pending.append(Pending(bytes: bytes, channel: channel, at: at, sourceID: sourceID, completion: completion))
            if !self.paused { self.drain() }
        }
    }
    public func retry() {
        worker.async {
            guard self.paused else { return }
            self.paused = false
            self.drain()
            if !self.paused { DispatchQueue.main.async(execute: self.onRecovery) }
        }
    }
    /// Stop this writer after all preceding writes. Used only for explicit erasure.
    public func stop() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            worker.async {
                self.paused = false; self.drain()
                if self.paused {
                    continuation.resume(throwing: QueueError.sql("Save pending recordings before deleting your account."))
                } else {
                    self.paused = true
                    continuation.resume()
                }
            }
        }
    }
    private func drain() {
        while head < pending.count {
            let frame = pending[head]
            do { try save(frame.bytes, frame.channel, frame.at, frame.sourceID) }
            catch {
                paused = true
                DispatchQueue.main.async { self.onFailure(error) }
                return
            }
            head += 1
            DispatchQueue.main.async(execute: frame.completion)
        }
        pending.removeAll(keepingCapacity: true); head = 0
    }
}
