import Combine
import Foundation
import SwiftUI

/// Wires the strap manager to the local queue and the uploader.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var queued = 0
    @Published private(set) var uploadStats = Uploader.Stats()
    @Published private(set) var queueError: String?

    let strap = StrapManager()
    private let queue: FrameQueue?
    private let uploader: Uploader?
    private var flushTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    static let flushInterval: TimeInterval = 60

    init() {
        do {
            let queue = try FrameQueue(path: try FrameQueue.defaultPath())
            self.queue = queue
            uploader = Uploader(queue: queue)
            queued = (try? queue.count()) ?? 0
        } catch {
            queue = nil
            uploader = nil
            queueError = "queue unavailable: \(error)"
        }

        strap.onFrame = { [weak self] bytes, channel in
            Task { @MainActor in self?.enqueue(bytes, channel: channel) }
        }
        strap.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)

        flushTimer = Timer.scheduledTimer(withTimeInterval: Self.flushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.flush() }
        }
    }

    private func enqueue(_ bytes: [UInt8], channel: Int) {
        guard let queue else { return }
        do {
            try queue.enqueue(bytes, channel: channel)
            queued += 1
            if queued >= Uploader.batchSize { Task { await flush() } }
        } catch {
            queueError = "enqueue failed: \(error)"
        }
    }

    func flush() async {
        guard let uploader, let queue, Settings.isConfigured, !strap.serial.isEmpty else { return }
        uploadStats = await uploader.flush(deviceId: strap.serial, model: strap.model, firmware: strap.firmware)
        queued = (try? queue.count()) ?? queued
    }
}
