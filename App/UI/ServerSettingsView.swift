import SwiftUI

struct ServerSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var deleting = false
    var body: some View {
        Form {
            ServerSignInSection()
            if Settings.credential?.accountID != nil {
                Section {
                    Button("Delete account", role: .destructive) { deleting = true }
                }
            }
            Section("Setup") {
                Button("Show the welcome guide again") { model.isOnboarded = false }
            }
        }
        .scrollContentBackground(.hidden).zoopScreen()
        .sheet(isPresented: $deleting) { DeleteAccountView() }
        .navigationTitle("Server connection").navigationBarTitleDisplayMode(.inline)
    }
}

struct ServerSignInSection: View {
    @State private var server = Settings.credential?.server ?? UserDefaults.standard.string(forKey: Settings.serverURLKey) ?? ""
    @State private var email = ""
    @State private var password = ""
    @State private var credential = Settings.credential
    @State private var busy = false
    @State private var replacingLegacy = false
    @State private var error: String?
    var body: some View {
        Section("Zoop server") {
            if let credential, !replacingLegacy {
                Text(credential.email ?? "Connected")
                Text(credential.server).foregroundStyle(ZoopStyle.secondary)
                if credential.accountID == nil {
                    Button("Sign in with account") { replacingLegacy = true }
                }
                Button("Sign out", role: .destructive) { perform { try await ServerSignIn.signOut() } }
            } else {
                TextField("Server URL", text: $server, prompt: Text("https://zoop.example.net"))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Email", text: $email).textContentType(.username)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password", text: $password).textContentType(.password)
                Button("Sign in") { perform { try await ServerSignIn.signIn(server: server, email: email, password: password); password = ""; replacingLegacy = false } }
                    .disabled(server.isEmpty || email.isEmpty || password.isEmpty)
            }
            if server.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http://") {
                Text("HTTP connection · Use a trusted network or VPN.").font(.footnote).foregroundStyle(ZoopStyle.secondary)
            }
            if busy { ProgressView().accessibilityLabel("Connecting") }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .disabled(busy)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in credential = Settings.credential }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true; error = nil
        Task { @MainActor in
            defer { busy = false; credential = Settings.credential }
            do { try await action() } catch { self.error = error.localizedDescription }
        }
    }
}
