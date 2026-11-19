import Foundation

/// Framework completion handlers may be invoked from any queue, once. This box
/// owns that boundary explicitly instead of transferring framework objects to UI tasks.
public final class CompletionOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (() -> Void)?
    public init(_ action: @escaping () -> Void) { self.action = action }
    public func call() {
        lock.lock(); let callback = action; action = nil; lock.unlock()
        callback?()
    }
}
