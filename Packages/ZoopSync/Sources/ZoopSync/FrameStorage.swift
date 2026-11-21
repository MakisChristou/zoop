import Foundation

/// SQLite setup and diagnostic reads never contend for disk or locks on the UI executor.
public actor FrameStorage {
    public struct Counts: Sendable { public let queued: Int; public let held: Int; public let unassigned: Int }
    private var queue: FrameQueue?
    public init() {}
    public func open(path: URL? = nil) throws -> FrameQueue {
        if let queue { return queue }
        let opened = try FrameQueue(path: try path ?? FrameQueue.defaultPath())
        queue = opened; return opened
    }
    public func counts() throws -> Counts {
        let queue = try open()
        return try Counts(queued: queue.count(), held: queue.heldCount(), unassigned: queue.unassignedCount())
    }
    public func bind(sourceID: String, deviceID: String, adoptLegacy: Bool = false) throws {
        try open().bind(sourceID: sourceID, deviceID: deviceID, adoptLegacy: adoptLegacy)
    }
    public func eraseDevices(_ devices: [String]) throws { try open().eraseDevices(devices) }
    public func retryHeld() throws { try open().retryHeld() }
}
