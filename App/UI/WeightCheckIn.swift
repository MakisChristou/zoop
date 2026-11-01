import SwiftUI
struct WeightCheckIn: View {
    @EnvironmentObject private var model: AppModel
    @State private var showHistory = false
    @AppStorage("weightUnit") private var unit = "kg"
    var body: some View {
        Button { if model.health.today == nil { model.health.showWeightEntry = true } else { showHistory = true } } label: {
            HStack(spacing: 12) {
                Image(systemName: "scalemass").foregroundStyle(SnoopStyle.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.health.today == nil ? "Log your weight" : "Weight logged").font(.subheadline.weight(.semibold))
                    if let today = model.health.today {
                        Text("\((unit == "lb" ? today.kg * 2.2046226218 : today.kg).formatted(.number.precision(.fractionLength(1)))) \(unit) · \(today.sourceName)")
                            .font(.caption).foregroundStyle(SnoopStyle.secondary)
                    }
                }
                Spacer()
                Image(systemName: model.health.today == nil ? "plus" : "checkmark").foregroundStyle(SnoopStyle.load)
            }.frame(minHeight: 44).snoopCard(padding: 12)
        }.buttonStyle(PressableCardStyle()).accessibilityIdentifier("weightCheckIn")
        .sheet(isPresented: $showHistory) { ProfileSheet(open: .weight) }
    }
}
