import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Settings.serverURLKey) private var serverURL = ""
    @AppStorage(Settings.ingestTokenKey) private var ingestToken = ""
    @State private var testResult: String?
    @State private var testing = false
    @State private var profile = SnoopAPI.Profile.empty
    @State private var profileStatus: String?
    @State private var savingProfile = false
    @State private var birthYearText = ""
    @State private var weightText = ""
    @State private var heightText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("snoop-api") {
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
                            if testing { ProgressView() } else if let testResult { Text(testResult).foregroundStyle(.secondary) }
                        }
                    }
                    .disabled(testing || serverURL.isEmpty)
                }
                Section {
                    Text("Frames are queued on this phone and uploaded in batches. Nothing leaves the device until a server is configured.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                profileSection
                Section("Setup") {
                    Button("Show the welcome guide again") {
                        UserDefaults.standard.set(false, forKey: AppModel.onboardedKey)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
            .task { await loadProfile() }
        }
    }

    /// Body profile for calories and heart-rate zones. Lives on the server so every
    /// recompute and any other client sees the same inputs.
    private var profileSection: some View {
        Section {
            Picker("Sex", selection: $profile.sex) {
                Text("Not set").tag(String?.none)
                Text("Male").tag(String?.some("male"))
                Text("Female").tag(String?.some("female"))
            }
            LabeledContent("Birth year") {
                TextField("1990", text: $birthYearText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("Weight") {
                HStack(spacing: 4) {
                    TextField("75", text: $weightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Text("kg").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Height") {
                HStack(spacing: 4) {
                    TextField("175", text: $heightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Text("cm").foregroundStyle(.secondary)
                }
            }
            Button {
                Task { await saveProfile() }
            } label: {
                HStack {
                    Label("Save profile", systemImage: "person.crop.circle")
                    Spacer()
                    if savingProfile { ProgressView() } else if let profileStatus { Text(profileStatus).foregroundStyle(.secondary) }
                }
            }
            .disabled(savingProfile || !Settings.isConfigured || model.strap.serial.isEmpty)
        } header: {
            Text("Profile")
        } footer: {
            Text("Calories and heart-rate zones need sex, birth year and weight. Days are cut in this phone's time zone (\(TimeZone.current.identifier)).")
        }
    }

    private func loadProfile() async {
        guard Settings.isConfigured, !model.strap.serial.isEmpty else { return }
        guard let fetched = try? await SnoopAPI.profile(deviceId: model.strap.serial) else { return }
        profile = fetched ?? .empty
        birthYearText = profile.birthYear.map(String.init) ?? ""
        weightText = profile.weightKg.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
        heightText = profile.heightCm.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? ""
    }

    private func saveProfile() async {
        savingProfile = true
        defer { savingProfile = false }
        profile.birthYear = Int(birthYearText.trimmingCharacters(in: .whitespaces))
        profile.weightKg = Double(weightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        profile.heightCm = Double(heightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        profile.tz = TimeZone.current.identifier
        do {
            profile = try await SnoopAPI.saveProfile(deviceId: model.strap.serial, profile)
            profileStatus = "✓ Saved"
        } catch {
            profileStatus = "Not saved: \(error.localizedDescription)"
        }
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
            case 200: testResult = "✓ Connected"
            case 401: testResult = "Reachable, token rejected"
            case let code?: testResult = "HTTP \(code)"
            case nil: testResult = "No response"
            }
        } catch {
            testResult = "Unreachable: \(error.localizedDescription)"
        }
    }
}
