import SwiftUI

/// Server URL and token, with a connection test. Pushed from the profile sheet's
/// Advanced group; the onboarding flow collects the same two values on first run.
struct ServerSettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Settings.serverURLKey) private var serverURL = ""
    @AppStorage(Settings.ingestTokenKey) private var ingestToken = ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $serverURL, prompt: Text("https://snoop.example.net"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Bearer token", text: $ingestToken)
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Label("Test connection", systemImage: "network")
                        Spacer()
                        if testing { ProgressView() } else if let testResult { Text(testResult).foregroundStyle(SnoopStyle.secondary) }
                    }
                }
                .disabled(testing || serverURL.isEmpty)
            } header: {
                Text("snoop-api")
            } footer: {
                Text("Frames are queued on this phone and uploaded in batches. Nothing leaves the device until a server is configured.")
            }
            Section("Setup") {
                Button("Show the welcome guide again") {
                    model.isOnboarded = false
                }
            }
        }
        .scrollContentBackground(.hidden)
        .snoopScreen()
        .navigationTitle("Server connection")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Hits `/health` (no auth) and then an authenticated endpoint, so a bad URL and a
    /// bad token produce different messages.
    private func testConnection() async {
        testing = true
        defer { testing = false }
        guard let base = URL(string: serverURL) else { testResult = "Invalid URL"; return }
        do {
            var healthRequest = URLRequest(url: base.appendingPathComponent("health"))
            healthRequest.timeoutInterval = 15
            let (_, health) = try await URLSession.shared.data(for: healthRequest)
            guard (health as? HTTPURLResponse)?.statusCode == 200 else { testResult = "Server not reachable"; return }
            var request = URLRequest(url: base.appendingPathComponent("v1/devices/_/latest"))
            request.timeoutInterval = 15
            request.setValue("Bearer \(ingestToken)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await URLSession.shared.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200: testResult = "Connected"
            case 401: testResult = "Reachable, token rejected"
            case let code?: testResult = "HTTP \(code)"
            case nil: testResult = "No response"
            }
        } catch {
            testResult = "Unreachable: \(error.localizedDescription)"
        }
    }
}
