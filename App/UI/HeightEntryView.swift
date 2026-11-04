import SwiftUI

/// Edits the profile's draft, just like the previous inline field. The parent
/// retains its existing explicit Save profile action and server validation.
struct HeightEntryView: View {
    @Binding var height: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft = ""
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 56.0
    private var number: Double? { Double(draft.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")) }
    private var rulerValue: Binding<Double> {
        Binding(get: { number ?? 175 }, set: { draft = $0.formatted(.number.precision(.fractionLength(0))) })
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Your height").font(.title2.weight(.semibold)).padding(.top, 20)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TextField("Not set", text: $draft).keyboardType(.decimalPad).focused($focused)
                            .font(.system(size: min(numberSize, 88), weight: .medium)).monospacedDigit()
                            .multilineTextAlignment(.center).frame(maxWidth: 240)
                            .accessibilityLabel("Height in centimetres").accessibilityIdentifier("heightInput")
                            .accessibilityHint("Tap to type a height")
                        Text("cm").foregroundStyle(SnoopStyle.secondary)
                    }
                    MeasurementRuler(value: rulerValue, range: 40...250, step: 1, unit: "cm", label: "Height ruler", onEditing: { focused = false })
                        .accessibilityIdentifier("heightRuler")
                }.padding(.horizontal, SnoopStyle.gutter).padding(.bottom, 20)
            }
            .safeAreaInset(edge: .bottom) {
                Button { height = draft; dismiss() } label: {
                    Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                }.buttonStyle(.borderedProminent).disabled(!draft.isEmpty && number?.isFinite != true)
                    .padding(.horizontal, SnoopStyle.gutter).padding(.vertical, 12).background(SnoopStyle.background)
            }
            .navigationTitle("Height").navigationBarTitleDisplayMode(.inline).snoopScreen().tint(SnoopStyle.load)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { draft = height }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}
