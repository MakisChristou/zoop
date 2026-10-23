import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Settings.serverURLKey) private var serverURL = ""
    @AppStorage(Settings.ingestTokenKey) private var ingestToken = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("snoop-api") {
                    TextField("Server URL", text: $serverURL, prompt: Text("https://snoop.example.net"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Bearer token", text: $ingestToken)
                }
                Section {
                    Text("Frames are queued on this phone and uploaded in batches. Nothing leaves the device until a server is configured.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
