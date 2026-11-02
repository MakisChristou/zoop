import SwiftUI
import SnoopHealth

struct WeightView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var adding = false
    @State private var importing = false
    private var rows: [WeightReading] { model.health.rows }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if rows.isEmpty { empty } else {
                    WeightTrendChart(readings: rows, unit: unit)
                    NavigationLink { WeightHistoryView() } label: {
                        HStack {
                            Text("All weigh-ins").font(.body.weight(.medium))
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("weightHistory")
                }
                if !model.health.journal.pendingWeights.isEmpty {
                    Label("Saved on this iPhone · waiting to sync", systemImage: "icloud.and.arrow.up")
                        .font(.footnote).foregroundStyle(SnoopStyle.secondary)
                }
                if let error = model.health.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.footnote).foregroundStyle(SnoopStyle.unfavourable)
                        Button("Retry sync") { model.health.checkSoon() }.disabled(model.health.busy)
                    }.snoopCard()
                }
            }.padding(.horizontal, SnoopStyle.gutter).padding(.vertical, 20)
        }
        .snoopScreen().tint(SnoopStyle.load)
        .navigationTitle("Weight").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Log weight").accessibilityIdentifier("logWeight")
            }
            ToolbarItem(placement: .topBarTrailing) { options }
        }
        .refreshable { await model.health.sync() }
        .sheet(isPresented: $adding) { WeightEntryView() }
        .sheet(isPresented: $importing) { WeightImportView() }
    }
    private var empty: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "scalemass").font(.largeTitle).foregroundStyle(SnoopStyle.secondary)
            Text("Your weight, over time").font(.title2.weight(.semibold))
            Text("Bring in your Apple Health weigh-ins, or log your first measurement.")
                .foregroundStyle(SnoopStyle.secondary)
            Button { importing = true } label: {
                Text("Import weight history").foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            }.buttonStyle(.borderedProminent)
            Button("Log first weight") { adding = true }
        }.frame(maxWidth: .infinity, alignment: .leading).snoopCard()
    }
    private var options: some View {
        Menu {
            Picker("Unit", selection: $unit) { Text("Kilograms").tag("kg"); Text("Pounds").tag("lb") }
            Toggle("Remind me after waking", isOn: Binding(get: { model.health.canRemind }, set: { model.health.setReminder($0) }))
            Button("Import weight history", systemImage: "heart") { importing = true }
        } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("Weight options")
    }
}
