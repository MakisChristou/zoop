import Foundation
import Observation

/// Setup navigation owns only transient form state. Preview never invokes live actions.
@MainActor @Observable
final class SetupFlow {
    enum Mode { case firstRun, preview }
    enum Step: Int, CaseIterable { case welcome, server, band, ready }
    struct Actions {
        var signIn: @MainActor (String, String, String) async throws -> Void
        var connect: @MainActor () -> Void
        var finish: @MainActor () -> Void
    }

    let mode: Mode
    private let actions: Actions
    private(set) var step: Step = .welcome
    private(set) var signedIn: Bool
    private(set) var busy = false
    private(set) var requestedConnection = false
    private(set) var previewConnected = false
    private(set) var finished = false
    private(set) var error: String?
    var server: String
    var email = ""
    var password = ""

    init(mode: Mode, signedIn: Bool = false, server: String = "", actions: Actions) {
        self.mode = mode
        self.signedIn = mode == .preview ? false : signedIn
        self.server = mode == .preview ? "https://zoop.example.com" : server
        self.actions = actions
        if mode == .preview { email = "you@example.com"; password = "preview-password" }
    }

    static func preview() -> SetupFlow {
        .init(mode: .preview, actions: .init(signIn: { _, _, _ in }, connect: {}, finish: {}))
    }

    var canSignIn: Bool {
        signedIn || (!server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty)
    }

    func begin() { guard step == .welcome else { return }; step = .server }

    func signIn() async {
        guard step == .server, !busy, canSignIn else { return }
        error = nil
        if !signedIn {
            busy = true
            defer { busy = false }
            do {
                if mode == .firstRun { try await actions.signIn(server, email, password) }
                signedIn = true
                password = ""
            } catch { self.error = error.localizedDescription; return }
        }
        step = .band
    }

    func connect(alreadyConnected: Bool) {
        guard step == .band, signedIn else { return }
        error = nil
        if alreadyConnected { step = .ready; return }
        requestedConnection = true
        if mode == .preview { previewConnected = true; step = .ready }
        else { actions.connect() }
    }

    func connectionBecameReady() {
        guard step == .band, requestedConnection, signedIn else { return }
        step = .ready
    }

    func skipBand() { guard step == .band, signedIn else { return }; step = .ready }

    func finish() {
        guard step == .ready, signedIn, !finished else { return }
        finished = true
        if mode == .firstRun { actions.finish() }
    }

    func back() {
        guard !busy, step != .welcome else { return }
        error = nil
        step = Step(rawValue: step.rawValue - 1) ?? .welcome
    }
}
