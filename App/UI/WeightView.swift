import SwiftUI
import ZoopHealth

struct WeightView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var adding = false
    @State private var editing: WeightReading?
    @State private var importing = false
    @State private var options = false
    private var rows: [WeightReading] { model.health.rows }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if rows.isEmpty { empty } else {
                    WeightTrendChart(readings: rows, unit: unit, target: CutTargets.weight(goal: model.weeklyWeight.goal, summary: model.weeklyWeight.summary), logWeight: { adding = true }, openReading: { editing = $0 })
                }
                if !model.health.journal.pendingWeights.isEmpty {
                    Label("Saved on this iPhone · waiting to sync", systemImage: "icloud.and.arrow.up").font(.footnote).foregroundStyle(ZoopStyle.secondary)
                }
                if let error = model.health.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.footnote).foregroundStyle(ZoopStyle.unfavourable)
                        Button("Retry sync") { model.health.checkSoon() }.disabled(model.health.busy)
                    }.zoopCard()
                }
            }.padding(.horizontal, ZoopStyle.gutter).padding(.vertical, 16)
        }.accessibilityIdentifier("weightScroll").zoopScreen().tint(ZoopStyle.text)
        .navigationTitle("Weight").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { options = true } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Weight options")
            }
        }
        .refreshable { await model.health.sync() }
        .sheet(isPresented: $adding) { WeightEntryView() }
        .sheet(item: $editing) { WeightEntryView(editing: $0) }
        .sheet(isPresented: $importing) { WeightImportView() }
        .sheet(isPresented: $options) { WeightOptionsView() }
    }
    private var empty: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "chart.xyaxis.line").font(.largeTitle).foregroundStyle(ZoopStyle.load)
            Text("No weigh-ins yet").font(.title2.weight(.medium))
            Button { adding = true } label: {
                Text("Log your weight").font(.headline).frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            }.buttonStyle(.borderedProminent).accessibilityIdentifier("logWeight")
            Button("Import weight history") { importing = true }.frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.bordered)
        }.padding(.vertical, 20)
    }
}
