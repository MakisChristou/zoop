import SwiftUI

/// Only the first-run adapter has access to live services. The preview has none.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    var body: some View { LiveSetupView(model: model) }
}

private struct LiveSetupView: View {
    let model: AppModel
    @State private var flow: SetupFlow

    init(model: AppModel) {
        self.model = model
        _flow = State(initialValue: SetupFlow(mode: .firstRun,
            signedIn: Settings.isConfigured, server: Settings.credential?.server ?? "",
            actions: .init(signIn: { server, email, password in
                try await ServerSignIn.signIn(server: server, email: email, password: password)
            }, connect: {
                model.startStrap()
                // start() is idempotent; connect() also retries an already-started manager.
                if model.strap.state != .ready { model.strap.connect() }
            }, finish: { model.isOnboarded = true })))
    }

    private var band: SetupBandStatus {
        switch model.strap.state {
        case .ready:
            guard Settings.permitsDevice(model.strap.serial) else {
                return .blocked("Ask your server administrator to assign this WHOOP to your account, then sign in again.")
            }
            return .connected(model.strap.model.isEmpty ? "WHOOP" : "WHOOP \(model.strap.model)")
        case .bluetoothOff: return .blocked("Turn on Bluetooth in iPhone Settings. If access is disabled, allow it for Zoop.")
        case .failed(let reason): return flow.requestedConnection ? .blocked(reason) : .idle
        case .scanning, .connecting, .connected: return flow.requestedConnection ? .searching : .idle
        }
    }

    var body: some View {
        SetupFlowView(flow: flow, band: band, syncing: model.isUploading)
            .onChange(of: band, initial: true) { _, status in
                if status.isConnected { flow.connectionBecameReady() }
            }
    }
}

/// Can be presented over the existing app without changing onboarding or account state.
struct SetupPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var flow = SetupFlow.preview()
    var body: some View {
        SetupFlowView(flow: flow, band: flow.previewConnected ? .connected("WHOOP MG") : .idle,
                      syncing: flow.previewConnected, close: { dismiss() })
            .onChange(of: flow.finished) { _, finished in if finished { dismiss() } }
    }
}

enum SetupBandStatus: Equatable {
    case idle, searching, connected(String), blocked(String)
    var isConnected: Bool { if case .connected = self { true } else { false } }
    var name: String { if case .connected(let name) = self { name } else { "WHOOP" } }
}
