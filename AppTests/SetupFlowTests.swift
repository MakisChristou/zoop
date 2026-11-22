import XCTest
@testable import Zoop

@MainActor final class SetupFlowTests: XCTestCase {
    @MainActor private final class Calls {
        var signIns = 0
        var connects = 0
        var finishes = 0
        var reject = false
        var submitted: [String] = []
        enum Rejected: Error { case login }
        var actions: SetupFlow.Actions {
            .init(signIn: { server, email, password in
                self.signIns += 1
                self.submitted = [server, email, password]
                if self.reject { throw Rejected.login }
            }, connect: { self.connects += 1 }, finish: { self.finishes += 1 })
        }
    }

    func testPreviewIgnoresLiveActionsAndAccountStateEvenWhenProvided() async {
        let calls = Calls()
        calls.reject = true
        let flow = SetupFlow(mode: .preview, signedIn: true, server: "https://private.invalid", actions: calls.actions)
        XCTAssertFalse(flow.signedIn)
        XCTAssertEqual(flow.server, "https://zoop.example.com")
        flow.begin(); await flow.signIn()
        XCTAssertEqual(flow.step, .band)
        flow.connect(alreadyConnected: false)
        XCTAssertTrue(flow.previewConnected)
        XCTAssertEqual(flow.step, .ready)
        flow.finish(); flow.finish()
        XCTAssertTrue(flow.finished)
        XCTAssertEqual(calls.signIns, 0); XCTAssertEqual(calls.connects, 0); XCTAssertEqual(calls.finishes, 0)
    }

    func testAbandoningAndReopeningPreviewDoesNotWriteDefaults() async {
        let before = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
        var flow: SetupFlow? = .preview()
        flow?.begin(); await flow?.signIn()
        flow?.connect(alreadyConnected: false)
        flow = nil
        let again = SetupFlow.preview()
        XCTAssertEqual(again.step, .welcome)
        XCTAssertFalse(again.signedIn)
        XCTAssertFalse(again.previewConnected)
        XCTAssertEqual(before, UserDefaults.standard.dictionaryRepresentation() as NSDictionary)
    }

    func testFailedLoginStaysOnFormAndRetryClearsPassword() async {
        let calls = Calls(); calls.reject = true
        let flow = SetupFlow(mode: .firstRun, actions: calls.actions)
        flow.begin(); flow.server = "https://example.test"; flow.email = "test@example.test"; flow.password = "test-password"
        await flow.signIn()
        XCTAssertEqual(flow.step, .server); XCTAssertFalse(flow.signedIn); XCTAssertNotNil(flow.error); XCTAssertFalse(flow.busy)
        calls.reject = false
        await flow.signIn()
        XCTAssertEqual(calls.submitted, ["https://example.test", "test@example.test", "test-password"])
        XCTAssertEqual(flow.step, .band); XCTAssertTrue(flow.signedIn); XCTAssertNil(flow.error); XCTAssertEqual(flow.password, "")
        XCTAssertEqual(calls.signIns, 2); XCTAssertEqual(calls.connects, 0); XCTAssertEqual(calls.finishes, 0)
    }

    func testCannotSkipRequiredServerOrFinishBeforeReady() async {
        let calls = Calls(); let flow = SetupFlow(mode: .firstRun, actions: calls.actions)
        flow.connect(alreadyConnected: true); flow.skipBand(); flow.finish()
        XCTAssertEqual(flow.step, .welcome)
        flow.begin(); await flow.signIn(); flow.skipBand(); flow.finish()
        XCTAssertEqual(flow.step, .server); XCTAssertFalse(flow.finished)
        XCTAssertEqual(calls.signIns, 0); XCTAssertEqual(calls.connects, 0); XCTAssertEqual(calls.finishes, 0)
    }

    func testExistingAccountAndBandAreReusedWithoutReconnectOrLogin() async {
        let calls = Calls(); let flow = SetupFlow(mode: .firstRun, signedIn: true, actions: calls.actions)
        flow.begin(); await flow.signIn(); flow.connect(alreadyConnected: true); flow.finish()
        XCTAssertEqual(flow.step, .ready)
        XCTAssertEqual(calls.signIns, 0); XCTAssertEqual(calls.connects, 0); XCTAssertEqual(calls.finishes, 1)
    }

    func testSkippingBandDoesNotConnectAndFinishesExactlyOnce() async {
        let calls = Calls(); let flow = SetupFlow(mode: .firstRun, signedIn: true, actions: calls.actions)
        flow.begin(); await flow.signIn(); flow.skipBand(); flow.finish(); flow.finish()
        XCTAssertEqual(calls.connects, 0); XCTAssertEqual(calls.finishes, 1)
    }

    func testConnectionWaitsForRealReadyAndBackDoesNotTriggerActions() async {
        let calls = Calls(); let flow = SetupFlow(mode: .firstRun, signedIn: true, actions: calls.actions)
        flow.begin(); await flow.signIn()
        flow.connectionBecameReady() // An unrelated event before the user taps Connect.
        XCTAssertEqual(flow.step, .band)
        flow.connect(alreadyConnected: false)
        XCTAssertEqual(flow.step, .band); XCTAssertEqual(calls.connects, 1)
        flow.connectionBecameReady(); XCTAssertEqual(flow.step, .ready)
        flow.back(); flow.back(); XCTAssertEqual(flow.step, .server)
        await flow.signIn(); XCTAssertEqual(calls.signIns, 0)
        XCTAssertEqual(calls.connects, 1); XCTAssertEqual(calls.finishes, 0)
    }

    func testDuplicateSignInAndBackAreIgnoredWhileRequestIsInFlight() async {
        var continuation: CheckedContinuation<Void, Never>?
        var calls = 0
        let flow = SetupFlow(mode: .firstRun, actions: .init(signIn: { _, _, _ in
            calls += 1
            await withCheckedContinuation { continuation = $0 }
        }, connect: {}, finish: {}))
        flow.begin(); flow.server = "https://example.test"; flow.email = "test"; flow.password = "test"
        let first = Task { await flow.signIn() }
        while !flow.busy { await Task.yield() }
        flow.back(); await flow.signIn()
        XCTAssertEqual(flow.step, .server); XCTAssertEqual(calls, 1)
        continuation?.resume(); await first.value
        XCTAssertEqual(flow.step, .band); XCTAssertFalse(flow.busy)
    }
}
