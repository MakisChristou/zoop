import SwiftUI

struct CutProgressView: View {
    let progress: SnoopAPI.CutProgress
    let unit: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
            layout {
                value((progress.totalLostKg ?? 0) < 0 ? "Total gained" : "Total lost", WeeklyWeightPresentation.weight(progress.totalLostKg.map(abs), unit: unit) + (progress.totalLostKg == nil ? "" : " " + unit))
                if let weeks = progress.weeksRemaining {
                    value(progress.completed ? "Finished" : "Remaining", progress.completed ? "Cut ended" : weeks == 0 ? "Last day" : "\(weeks) \(weeks == 1 ? "week" : "weeks")")
                }
            }
            if let end = progress.finishDate, let date = WeeklyWeightPresentation.date(end) {
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack { Text("Target \(WeeklyWeightPresentation.weight(progress.targetWeightKg, unit: unit))\(progress.targetWeightKg == nil ? "" : " " + unit)"); Spacer(); Text(date.formatted(.dateTime.day().month(.abbreviated).year())) }
                    VStack(alignment: .leading, spacing: 4) { Text("Target \(WeeklyWeightPresentation.weight(progress.targetWeightKg, unit: unit))\(progress.targetWeightKg == nil ? "" : " " + unit)"); Text(date.formatted(.dateTime.day().month(.abbreviated).year())) }
                }.font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            }
        }.snoopCard().accessibilityIdentifier("cutProgress")
    }
    private func value(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(label).font(.caption).foregroundStyle(SnoopStyle.secondary); Text(value).font(.title3.weight(.semibold)).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
