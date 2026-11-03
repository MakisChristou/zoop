import XCTest
import SnoopECG
import SnoopProtocol
@testable import Snoop

@MainActor private final class ECGTestTransport: ECGTransport {
    var ecgDevice: ECGDevice? = .init(serial: "TEST-MG", firmware: "test", isMG: true)
    var operations: [ECGOperation] = []
    var reject: ECGOperation?
    var suspend: ECGOperation?
    func performECG(_ operation: ECGOperation) async throws {
        operations.append(operation)
        if operation == suspend { try await Task.sleep(for: .seconds(30)) }
        if operation == reject { throw ECGTransportError.refused(operation.command.code, "failure") }
    }
}

@MainActor final class ECGRecorderTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "ECGTests.\(UUID().uuidString)"; defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
    }
    private func wait(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<400 { if condition() { return }; try await Task.sleep(for: .milliseconds(5)) }
        XCTFail("Condition not reached", file: file, line: line)
    }
    private func frame(_ index: UInt8) -> Data {
        var body = [UInt8](repeating: 0, count: 228)
        body[0] = 43; body[1] = 17; body[3] = index; body[24] = 2
        body[26] = index; body[28] = 255; body[29] = 255
        return Data(Frame.encode(inner: body, destination: 1, source: 0))
    }
    func testCompleteCaptureIsSavedOnlyAfterSamplesAndStopsExactlyOnce() async throws {
        let transport = ECGTestTransport(), journal = ECGJournal(directory: directory!)
        var now = 100.0
        let recorder = ECGRecorder(transport: transport, journal: journal, defaults: defaults, clock: { now }, captureDuration: 1)
        recorder.begin(); recorder.begin()
        try await wait { recorder.phase == .waiting }
        XCTAssertNil(recorder.savedRecording)
        recorder.receive(frame(1), at: Date(), uptime: now)
        try await wait { recorder.phase == .recording }
        now = 101.1; recorder.receive(frame(2), at: Date(), uptime: now)
        try await wait { !recorder.isBusy }
        XCTAssertEqual(recorder.phase, .saved)
        XCTAssertEqual(recorder.savedRecording?.filteredSamples, [1, -1, 2, -1])
        XCTAssertEqual(transport.operations, [.wrist(.left), .rawLive(true), .filteredLive(true), .generation(true), .generation(false), .filteredLive(false), .rawLive(false)])
        let stored = try await journal.summaries(device: "TEST-MG"), pending = try await journal.pending()
        XCTAssertEqual(stored.count, 1); XCTAssertTrue(pending.isEmpty)
    }
    func testWristRefusalNeverStartsOrTogglesOutputs() async throws {
        let transport = ECGTestTransport(); transport.reject = .wrist(.left)
        let recorder = ECGRecorder(transport: transport, journal: ECGJournal(directory: directory), defaults: defaults)
        recorder.begin(); try await wait { !recorder.isBusy }
        XCTAssertEqual(transport.operations, [.wrist(.left)])
        XCTAssertEqual(recorder.phase, .failed); XCTAssertTrue(recorder.error?.contains("123") == true)
    }
    func testCountdownAloneCannotCompleteWithoutDataAtEndOfWindow() async throws {
        let transport = ECGTestTransport(), journal = ECGJournal(directory: directory!)
        var now = 100.0
        let recorder = ECGRecorder(transport: transport, journal: journal, defaults: defaults, clock: { now }, captureDuration: 1)
        recorder.begin(); try await wait { recorder.phase == .waiting }
        recorder.receive(frame(1), at: Date(), uptime: now)
        now = 101.1
        try await wait { recorder.phase == .recording }
        XCTAssertNil(recorder.savedRecording)
        now = 106.1
        try await wait { !recorder.isBusy }
        XCTAssertEqual(recorder.phase, .failed)
        let recordings = try await journal.summaries(device: "TEST-MG")
        XCTAssertTrue(recordings.isEmpty)
    }
    func testGateRefusalCleansOnlyAttemptedGate() async throws {
        let transport = ECGTestTransport(); transport.reject = .rawLive(true)
        let recorder = ECGRecorder(transport: transport, journal: ECGJournal(directory: directory), defaults: defaults)
        recorder.begin(); try await wait { !recorder.isBusy }
        XCTAssertEqual(transport.operations, [.wrist(.left), .rawLive(true), .rawLive(false)])
        XCTAssertNil(recorder.savedRecording)
    }
    func testStartRefusalCleansGenerationAndBothGatesWithoutRepeatingStart() async throws {
        let transport = ECGTestTransport(); transport.reject = .generation(true)
        let recorder = ECGRecorder(transport: transport, journal: ECGJournal(directory: directory), defaults: defaults)
        recorder.begin(); try await wait { !recorder.isBusy }
        XCTAssertEqual(transport.operations.filter { $0 == .generation(true) }.count, 1)
        XCTAssertEqual(Array(transport.operations.suffix(3)), [.generation(false), .filteredLive(false), .rawLive(false)])
        XCTAssertEqual(recorder.phase, .failed)
    }
    func testAcceptedStartWithoutDataDoesNotSave() async throws {
        let transport = ECGTestTransport(), journal = ECGJournal(directory: directory!)
        let recorder = ECGRecorder(transport: transport, journal: journal, defaults: defaults, firstFrameTimeout: 0.05)
        recorder.begin(); try await wait { !recorder.isBusy }
        XCTAssertTrue(recorder.error?.contains("no filtered ECG") == true)
        let stored = try await journal.summaries(device: "TEST-MG")
        XCTAssertTrue(stored.isEmpty)
    }
    func testCancelDuringStartRunsCleanupInUncancelledTask() async throws {
        let transport = ECGTestTransport(); transport.suspend = .generation(true)
        let recorder = ECGRecorder(transport: transport, journal: ECGJournal(directory: directory), defaults: defaults)
        recorder.begin(); try await wait { transport.operations.contains(.generation(true)) }
        recorder.cancel(); try await wait { !recorder.isBusy }
        XCTAssertEqual(Array(transport.operations.suffix(3)), [.generation(false), .filteredLive(false), .rawLive(false)])
        XCTAssertNil(recorder.savedRecording); XCTAssertEqual(recorder.phase, .idle)
    }
    func testDisconnectLeavesCleanupForSameDeviceAndNeverAutoRestarts() async throws {
        let transport = ECGTestTransport(), journal = ECGJournal(directory: directory!)
        let recorder = ECGRecorder(transport: transport, journal: journal, defaults: defaults)
        recorder.begin(); try await wait { recorder.phase == .waiting }
        transport.ecgDevice = nil; recorder.connectionChanged()
        try await wait { !recorder.isBusy }
        XCTAssertTrue(recorder.cleanupNeeded)
        let starts = transport.operations.count
        transport.ecgDevice = .init(serial: "OTHER", firmware: nil, isMG: true)
        recorder.connectionChanged(); try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(transport.operations.count, starts)
        transport.ecgDevice = .init(serial: "TEST-MG", firmware: nil, isMG: true)
        recorder.connectionChanged()
        try await wait { transport.operations.contains(.rawLive(false)) && !recorder.isBusy }
        XCTAssertEqual(transport.operations.filter { $0 == .generation(true) }.count, 1)
        let pending = try await journal.pending(); XCTAssertTrue(pending.isEmpty)
    }
    func testStopFailureRetainsIntentAndBlocksNewStartUntilRecovered() async throws {
        let transport = ECGTestTransport(); transport.reject = .generation(false)
        let recorder = ECGRecorder(transport: transport, journal: ECGJournal(directory: directory), defaults: defaults)
        recorder.begin(); try await wait { recorder.phase == .waiting }
        recorder.cancel(); try await wait { !recorder.isBusy }
        XCTAssertTrue(recorder.cleanupNeeded); XCTAssertNotNil(recorder.cleanupError)
        let count = transport.operations.filter { $0 == .generation(true) }.count
        recorder.begin(); try await wait { !recorder.isBusy }
        XCTAssertEqual(transport.operations.filter { $0 == .generation(true) }.count, count)
        transport.reject = nil; recorder.recoverCleanup(); try await wait { !recorder.isBusy }
        XCTAssertFalse(recorder.cleanupNeeded)
    }
    func testStorageFailurePreventsEnablingECG() async throws {
        try Data([1]).write(to: directory)
        let transport = ECGTestTransport()
        let recorder = ECGRecorder(transport: transport, journal: ECGJournal(directory: directory), defaults: defaults)
        recorder.begin(); try await wait { !recorder.isBusy }
        XCTAssertFalse(transport.operations.contains(.rawLive(true)))
        XCTAssertFalse(transport.operations.contains(.generation(true)))
        XCTAssertEqual(recorder.phase, .failed)
    }
}
