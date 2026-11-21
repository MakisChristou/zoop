import SwiftUI

struct DeleteAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Permanently delete your account, recordings, health history, photo and shared links from this server.")
                    Text("Apple Health and files you exported stay unchanged. Server backups expire on your operator’s schedule.")
                        .foregroundStyle(ZoopStyle.secondary)
                }
                .listRowBackground(ZoopStyle.surface)
                Section {
                    SecureField("Confirm your password", text: $password).textContentType(.password)
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("Delete account", role: .destructive) {
                        busy = true; error = nil
                        Task { @MainActor in
                            defer { busy = false; password = "" }
                            do { try await model.deleteAccount(password: password); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(password.isEmpty || busy).accessibilityIdentifier("confirmDeleteAccount")
                    if busy { ProgressView().accessibilityLabel("Deleting account") }
                }
                .listRowBackground(ZoopStyle.surface)
            }
            .disabled(busy)
            .scrollContentBackground(.hidden).zoopScreen()
            .navigationTitle("Delete account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
        }
        .tint(ZoopStyle.text).interactiveDismissDisabled(busy)
        .presentationBackground(ZoopStyle.background)
    }
}
