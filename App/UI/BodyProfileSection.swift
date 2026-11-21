import SwiftUI
import ZoopHealth

/// Body profile rows for a `List`: sex, birth year, weight, height, and the save
/// button. Stored on the server with the phone's time zone so calories, zones and
/// local days line up everywhere.
struct BodyProfileSection: View {
    @Environment(AppModel.self) private var model
    @State private var profile = ZoopAPI.Profile.empty
    @State private var status: String?
    @State private var saving = false
    @State private var birthYearText = ""
    @State private var weightText = ""
    @State private var heightText = ""
    @State private var editingHeight = false
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var loadID = UUID()
    @State private var loaded = false
    @State private var loading = false
    @State private var loadFailed = false
    private var measuredWeight: WeightReading? {
        var readings = model.health.lastWeight.map { [$0] } ?? []
        if let at = profile.weightMeasuredAt, let kg = profile.weightKg {
            readings.append(.init(id: "profile", measuredAt: at, kg: kg, source: profile.weightSource ?? "health", sourceName: profile.weightSourceName ?? "Apple Health"))
        }
        return WeightReading.latest(readings)
    }

    var body: some View {
        Section {
            if loading { ZoopLoadingBar(label: "Loading profile") }
            Picker("Sex", selection: $profile.sex) {
                Text("Not set").tag(String?.none)
                Text("Male").tag(String?.some("male"))
                Text("Female").tag(String?.some("female"))
            }
            LabeledContent("Birth year") {
                TextField("1990", text: $birthYearText).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    .accessibilityLabel("Birth year")
            }
            if let weight = measuredWeight {
                NavigationLink { WeightView() } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        LabeledContent("Weight", value: "\((unit == "lb" ? weight.kg * 2.2046226218 : weight.kg).formatted(.number.precision(.fractionLength(1)))) \(unit)")
                        Text("\(weight.measuredAt.formatted(date: .abbreviated, time: .omitted)) · \(weight.source == "health" ? "Apple Health" : "Zoop")")
                            .font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                    }
                }.accessibilityIdentifier("profileLatestWeight")
            } else {
              LabeledContent("Weight") {
                HStack(spacing: 4) {
                    TextField("75", text: $weightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Weight in kilograms")
                    Text("kg").foregroundStyle(ZoopStyle.secondary)
                }
              }
            }
            Button { editingHeight = true } label: {
                HStack {
                    Text("Height").foregroundStyle(ZoopStyle.text)
                    Spacer()
                    Text(heightText.isEmpty ? "Not set" : "\(heightText) cm").foregroundStyle(ZoopStyle.secondary)
                    Image(systemName: "chevron.right").font(ZoopType.font(size: 12, weight: .semibold, relativeTo: .caption)).foregroundStyle(ZoopStyle.secondary)
                }.frame(minHeight: 44)
            }.accessibilityIdentifier("editHeight")
                .disabled(loading || !loaded)
                .sheet(isPresented: $editingHeight) { HeightEntryView(height: $heightText) }
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Label("Save profile", systemImage: "person.crop.circle")
                    Spacer()
                    if saving { ProgressView() } else if let status { Text(status).foregroundStyle(ZoopStyle.secondary) }
                }
            }
            .disabled(saving || loading || !loaded || !Settings.isConfigured || model.dataDevice.isEmpty)
            if loadFailed {
                Button("Couldn’t load profile. Retry") { Task { await load() } }
            }
        } header: {
            Text("Body")
        } footer: {
            Text("Used to estimate calories and heart-rate zones. Time zone: \(TimeZone.current.identifier).")
        }
        .task(id: "\(model.dataDevice)|\(Settings.connectionID)") { await load() }
        .onChange(of: model.health.lastWeight) { _, _ in Task { await load(preserveEdits: true) } }
    }

    private func load(preserveEdits: Bool = false) async {
        guard Settings.isConfigured, !model.dataDevice.isEmpty else { return }
        let serial = model.dataDevice, connection = Settings.connectionID, request = UUID()
        loadID = request; loading = true
        defer { if loadID == request { loading = false } }
        let fetched: ZoopAPI.Profile
        do { fetched = try await ZoopAPI.profile(deviceId: serial) ?? .empty }
        catch {
            if loadID == request, !Task.isCancelled { loadFailed = true }
            return
        }
        guard !Task.isCancelled, loadID == request, serial == model.dataDevice, connection == Settings.connectionID else { return }
        loadFailed = false
        if preserveEdits && loaded {
            profile.weightKg = fetched.weightKg; profile.weightMeasuredAt = fetched.weightMeasuredAt
            profile.weightSource = fetched.weightSource; profile.weightSourceName = fetched.weightSourceName
            return
        }
        profile = fetched
        birthYearText = profile.birthYear.map(String.init) ?? ""
        weightText = profile.weightKg.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
        heightText = profile.heightCm.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? ""
        loaded = true
    }

    private func save() async {
        saving = true
        defer { saving = false }
        profile.birthYear = Int(birthYearText.trimmingCharacters(in: .whitespaces))
        if measuredWeight == nil {
            profile.weightKg = Double(weightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        }
        profile.heightCm = Double(heightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        profile.tz = TimeZone.current.identifier
        do {
            let serial = model.dataDevice, connection = Settings.connectionID
            let saved = try await ZoopAPI.saveProfile(deviceId: serial, profile)
            guard serial == model.dataDevice, connection == Settings.connectionID else { return }
            profile = saved
            status = "Saved"
        } catch {
            status = "Not saved: \(error.localizedDescription)"
        }
    }
}
