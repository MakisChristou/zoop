import SwiftUI

/// Body profile rows for a `List`: sex, birth year, weight, height, and the save
/// button. Stored on the server with the phone's time zone so calories, zones and
/// local days line up everywhere.
struct BodyProfileSection: View {
    @Environment(AppModel.self) private var model
    @State private var profile = SnoopAPI.Profile.empty
    @State private var status: String?
    @State private var saving = false
    @State private var birthYearText = ""
    @State private var weightText = ""
    @State private var heightText = ""

    var body: some View {
        Section {
            Picker("Sex", selection: $profile.sex) {
                Text("Not set").tag(String?.none)
                Text("Male").tag(String?.some("male"))
                Text("Female").tag(String?.some("female"))
            }
            LabeledContent("Birth year") {
                TextField("1990", text: $birthYearText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    .accessibilityLabel("Birth year")
            }
            LabeledContent("Weight") {
                HStack(spacing: 4) {
                    TextField("75", text: $weightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Weight in kilograms")
                    Text("kg").foregroundStyle(SnoopStyle.secondary)
                }
            }
            LabeledContent("Height") {
                HStack(spacing: 4) {
                    TextField("175", text: $heightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Height in centimetres")
                    Text("cm").foregroundStyle(SnoopStyle.secondary)
                }
            }
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Label("Save profile", systemImage: "person.crop.circle")
                    Spacer()
                    if saving { ProgressView() } else if let status { Text(status).foregroundStyle(SnoopStyle.secondary) }
                }
            }
            .disabled(saving || !Settings.isConfigured || model.strap.serial.isEmpty)
        } header: {
            Text("Body")
        } footer: {
            Text("Used to estimate calories and heart-rate zones. Time zone: \(TimeZone.current.identifier).")
        }
        .task(id: model.strap.serial) { await load() }
    }

    private func load() async {
        guard Settings.isConfigured, !model.strap.serial.isEmpty else { return }
        guard let fetched = try? await SnoopAPI.profile(deviceId: model.strap.serial) else { return }
        profile = fetched
        birthYearText = profile.birthYear.map(String.init) ?? ""
        weightText = profile.weightKg.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
        heightText = profile.heightCm.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? ""
    }

    private func save() async {
        saving = true
        defer { saving = false }
        profile.birthYear = Int(birthYearText.trimmingCharacters(in: .whitespaces))
        profile.weightKg = Double(weightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        profile.heightCm = Double(heightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        profile.tz = TimeZone.current.identifier
        do {
            profile = try await SnoopAPI.saveProfile(deviceId: model.strap.serial, profile)
            status = "Saved"
        } catch {
            status = "Not saved: \(error.localizedDescription)"
        }
    }
}
