import Foundation

/// Serial persistence barrier shared by data and history-end frames. Completions
/// run in receive order on the main queue, only after each SQLite commit succeeds.
/// A failed write keeps that frame and everything behind it pending for retry.
public final class FrameWriter: @unchecked Sendable {
    private struct Pending {
        let bytes: [UInt8]; let channel: Int; let at: Date; let completion: () -> Void
    }
    private let worker = DispatchQueue(label: "snoop.frame-writer")
    private let save: ([UInt8], Int, Date) throws -> Void
    private let onFailure: (Error) -> Void
    private let onRecovery: () -> Void
    private var pending: [Pending] = []
    private var paused = false

    public init(save: @escaping ([UInt8], Int, Date) throws -> Void,
                onFailure: @escaping (Error) -> Void, onRecovery: @escaping () -> Void) {
        self.save = save; self.onFailure = onFailure; self.onRecovery = onRecovery
    }
    public func enqueue(_ bytes: [UInt8], channel: Int, at: Date = Date(), completion: @escaping () -> Void) {
        worker.async {
            self.pending.append(Pending(bytes: bytes, channel: channel, at: at, completion: completion))
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
    private func drain() {
        while let frame = pending.first {
            do { try save(frame.bytes, frame.channel, frame.at) }
            catch {
                paused = true
                DispatchQueue.main.async { self.onFailure(error) }
                return
            }
            pending.removeFirst()
            DispatchQueue.main.async(execute: frame.completion)
        }
    }
}
