import Foundation
import Observation
import OSLog
import SnoopECG
import SnoopProtocol

/// Owns one manual recording through setup, capture, durable save and cleanup.
/// Connection recovery only stops prior work; it never restarts a measurement.
@MainActor @Observable final class ECGRecorder {
    enum Phase: String, Equatable { case idle, starting, waiting, recording, finishing, saved, failed }
    private(set) var phase: Phase = .idle
    private(set) var samples: [Int32] = []
    private(set) var secondsRemaining = 30
    var onHistoryChanged: (() -> Void)?
    private(set) var recordings: [ECGRecordingSummary] = []
    private(set) var savedRecording: ECGRecording?
    private(set) var error: String?
    private(set) var cleanupError: String?
    private(set) var historyError: String?
    private(set) var cleanupNeeded = false
    private(set) var device: ECGDevice?
    private(set) var isBusy = false
    var wrist: ECGWrist {
        didSet { defaults.set(wrist.rawValue, forKey: "ecgWrist") }
    }

    @ObservationIgnored private let transport: ECGTransport
    @ObservationIgnored private let journal: ECGJournal
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: () -> TimeInterval
    @ObservationIgnored private let captureDuration: TimeInterval
    @ObservationIgnored private let firstFrameTimeout: TimeInterval
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var buffer = ECGBuffer()
    @ObservationIgnored private var captureDevice: ECGDevice?
    @ObservationIgnored private var acceptFramesAfter: TimeInterval?
    @ObservationIgnored private var captureFailure: String?
    @ObservationIgnored private var lastPublished: TimeInterval = 0
    @ObservationIgnored private var attemptEvents: [String] = []
    @ObservationIgnored private var historyDevice = ""
    @ObservationIgnored private let log = Logger(subsystem: "snoop", category: "ecg")

    var canStart: Bool { device?.isMG == true && !isBusy && !cleanupNeeded }
    var isRecording: Bool { [.starting, .waiting, .recording, .finishing].contains(phase) }

    init(transport: ECGTransport, journal: ECGJournal? = nil, defaults: UserDefaults = .standard,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         captureDuration: TimeInterval = ECGBuffer.duration, firstFrameTimeout: TimeInterval = 20) {
        self.transport = transport; self.defaults = defaults; self.clock = clock
        self.captureDuration = captureDuration; self.firstFrameTimeout = firstFrameTimeout
        self.journal = journal ?? ECGJournal(directory: URL.applicationSupportDirectory.appendingPathComponent("ECG", isDirectory: true))
        wrist = ECGWrist(rawValue: defaults.string(forKey: "ecgWrist") ?? "") ?? .left
        historyDevice = defaults.string(forKey: "ecgHistoryDevice") ?? ""
    }

    func connectionChanged() {
        device = transport.ecgDevice
        if let current = device {
            historyDevice = current.serial
            defaults.set(current.serial, forKey: "ecgHistoryDevice")
        }
        if let captureDevice, device?.serial != captureDevice.serial, isRecording {
            captureFailure = "WHOOP disconnected before the recording finished."
            task?.cancel()
        }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.reloadHistory()
            guard !Task.isCancelled else { return }
            if !self.isBusy { self.recoverCleanup() }
        }
    }

    func begin() {
        guard !isBusy else { return }
        device = transport.ecgDevice
        guard let current = device, current.isMG else {
            error = "Connect a WHOOP MG with an ECG-compatible clasp to record."; phase = .failed; return
        }
        guard !cleanupNeeded else { recoverCleanup(); return }
        phase = .starting; error = nil; cleanupError = nil; savedRecording = nil
        samples = []; buffer = ECGBuffer(); captureFailure = nil; captureDevice = current
        attemptEvents = []
        secondsRemaining = Int(ceil(captureDuration)); lastPublished = 0
        let selectedWrist = wrist
        isBusy = true
        task = Task { [weak self] in
            guard let self else { return }
            var completed: ECGRecording?
            await self.writeAttemptStatus()
            do {
                let pending = try await self.journal.pending()
                guard !pending.contains(where: { $0.device == current.serial && !$0.isEmpty }) else {
                    throw RecordingError.message("The previous recording needs to finish stopping. Try again after reconnecting.")
                }
                try await self.send(.wrist(selectedWrist), device: current)
                var intent = ECGCleanup(device: current.serial)
                intent.rawLive = true
                try await self.journal.setPending(intent)
                try await self.send(.rawLive(true), device: current)
                intent.filteredLive = true
                try await self.journal.setPending(intent)
                try await self.send(.filteredLive(true), device: current)
                intent.generation = true
                try await self.journal.setPending(intent)
                self.acceptFramesAfter = self.clock()
                try await self.send(.generation(true), device: current)
                self.phase = .waiting
                await self.writeAttemptStatus()
                let startedWaiting = self.clock()
                while true {
                    try Task.checkCancellation()
                    guard self.transport.ecgDevice?.serial == current.serial else { throw ECGTransportError.disconnected }
                    if let failure = self.captureFailure { throw RecordingError.message(failure) }
                    let now = self.clock()
                    if self.buffer.isStale(at: now) { throw RecordingError.message("ECG data stopped arriving. Keep both contacts lightly covered and try again.") }
                    if let first = self.buffer.firstSampleDate {
                        self.phase = .recording
                        let elapsed = self.buffer.elapsed(at: now)
                        self.secondsRemaining = Int(ceil(max(0, self.captureDuration - elapsed)))
                        let receivedSpan = (self.buffer.lastSampleUptime ?? now) - (self.buffer.firstSampleUptime ?? now)
                        if receivedSpan >= self.captureDuration {
                            completed = ECGRecording(device: current.serial, firmware: current.firmware, wrist: selectedWrist,
                                startedAt: first, duration: receivedSpan, frames: self.buffer.frames)
                            break
                        }
                    } else if now - startedWaiting > self.firstFrameTimeout {
                        throw RecordingError.message("WHOOP accepted the recording request, but no filtered ECG samples arrived. Keep both contacts lightly covered and try again.")
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
            } catch is CancellationError {
                self.error = self.captureFailure
            } catch {
                self.error = error.localizedDescription
            }
            self.acceptFramesAfter = nil
            self.phase = .finishing
            // An unstructured task is deliberately not cancelled with the capture task.
            let cleanup = Task { await self.cleanUp(device: current.serial) }
            await cleanup.value
            if let completed {
                self.savedRecording = completed
                do {
                    try await self.journal.save(completed)
                    self.log.info("ECG saved: frames=\(completed.frames.count) filteredSamples=\(self.buffer.filteredSamples.count)")
                    self.phase = .saved
                    await self.reloadHistory()
                } catch {
                    self.error = "The recording is still in memory but could not be saved. \(error.localizedDescription)"
                    self.phase = .failed
                }
            } else { self.phase = self.error == nil ? .idle : .failed }
            if let error = self.error { self.attemptEvents.append(error) }
            if let cleanupError = self.cleanupError { self.attemptEvents.append(cleanupError) }
            await self.writeAttemptStatus()
            self.buffer = ECGBuffer(); self.captureDevice = nil; self.task = nil; self.isBusy = false
        }
    }

    private func send(_ operation: ECGOperation, device: ECGDevice) async throws {
        try Task.checkCancellation()
        guard transport.ecgDevice?.serial == device.serial else { throw ECGTransportError.disconnected }
        try await transport.performECG(operation)
        attemptEvents.append("Command \(operation.command.code) accepted")
    }

    func receive(_ bytes: Data, at: Date, uptime: TimeInterval) {
        guard let after = acceptFramesAfter, uptime >= after,
              transport.ecgDevice?.serial == captureDevice?.serial else { return }
        do {
            if try buffer.receive(bytes, at: at, uptime: uptime), uptime - lastPublished >= 0.1 {
                samples = Array(buffer.filteredSamples.suffix(800)); lastPublished = uptime
            }
        } catch {
            captureFailure = "The ECG stream was incomplete. Please try another recording."
            log.error("ECG capture rejected a frame: \(String(describing: error), privacy: .public)")
        }
    }

    func invalidFrame() {
        if acceptFramesAfter != nil { captureFailure = "An ECG frame could not be read. Please try another recording." }
    }

    func cancel() { if isRecording { task?.cancel() } }
    func dismissResult() { guard !isBusy else { return }; phase = .idle; error = nil; savedRecording = nil }

    func retrySave() async {
        guard let recording = savedRecording, !isBusy else { return }
        do { try await journal.save(recording); phase = .saved; error = nil; await reloadHistory() }
        catch { self.error = "Couldn’t save the recording. \(error.localizedDescription)" }
    }

    func load(id: UUID) async throws -> ECGRecording { try await journal.recording(id: id) }

    func reloadHistory() async {
        let serial = historyDevice
        guard !serial.isEmpty else { return }
        do {
            let values = try await journal.summaries(device: serial)
            guard historyDevice == serial else { return }
            recordings = values; historyError = nil; onHistoryChanged?()
        } catch { if historyDevice == serial { historyError = "Couldn’t load recordings. \(error.localizedDescription)" } }
    }

    func recoverCleanup() {
        guard !isBusy, let current = transport.ecgDevice else { return }
        isBusy = true
        task = Task { [weak self] in
            guard let self else { return }
            await self.cleanUp(device: current.serial)
            self.task = nil; self.isBusy = false
        }
    }

    private func cleanUp(device serial: String) async {
        do {
            guard var pending = try await journal.pending().first(where: { $0.device == serial }) else {
                cleanupNeeded = false; cleanupError = nil; return
            }
            cleanupNeeded = !pending.isEmpty
            var failures: [String] = []
            for operation in pending.operations {
                guard transport.ecgDevice?.serial == serial else {
                    failures.append("Reconnect your WHOOP to finish stopping the recording."); break
                }
                do {
                    try await transport.performECG(operation)
                    attemptEvents.append("Cleanup \(operation.command.code) accepted")
                    pending.acknowledge(operation)
                    try await journal.setPending(pending)
                } catch { failures.append(error.localizedDescription) }
            }
            cleanupNeeded = try await journal.pending().contains { $0.device == serial && !$0.isEmpty }
            cleanupError = failures.isEmpty ? nil : failures.joined(separator: "\n")
            log.info("ECG cleanup complete=\(!self.cleanupNeeded)")
        } catch {
            cleanupNeeded = true
            cleanupError = "Couldn’t verify that the previous recording stopped. \(error.localizedDescription)"
        }
    }

    private enum RecordingError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
    }

    private func writeAttemptStatus() async {
        let status = ECGAttemptStatus(phase: phase.rawValue, events: Array(attemptEvents.suffix(20)),
            frameCount: buffer.frames.count, filteredSampleCount: buffer.filteredSamples.count, cleanupPending: cleanupNeeded)
        // Diagnostics never gate capture or replace the durable cleanup ledger.
        do { try await journal.writeAttemptStatus(status) }
        catch { log.error("Could not save ECG attempt diagnostics") }
    }
}
