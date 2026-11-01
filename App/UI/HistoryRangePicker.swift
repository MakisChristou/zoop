import SwiftUI

/// Explicit, mutually exclusive choices; custom dates appear only when needed.
struct HistoryRangePicker: View {
    @Binding var all: Bool
    @Binding var from: Date
    @Binding var to: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            choice("All history", detail: "Everything available", selected: all) { all = true }
            choice("Choose dates", detail: "Import a specific period", selected: !all) { all = false }
            if !all {
                VStack(spacing: 12) {
                    DatePicker("From", selection: $from, in: ...to, displayedComponents: .date)
                    Divider().overlay(SnoopStyle.separator)
                    DatePicker("Through", selection: $to, in: from...Date(), displayedComponents: .date)
                }.snoopCard()
            }
        }
    }
    private func choice(_ title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? SnoopStyle.load : SnoopStyle.secondary)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).snoopCard()
                .overlay(RoundedRectangle(cornerRadius: SnoopStyle.radius).strokeBorder(selected ? SnoopStyle.load : .clear, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
