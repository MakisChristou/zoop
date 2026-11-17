import SwiftUI

struct CutProgressView: View {
    let data: CutProgressData
    let unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let time = data.time {
                VStack(alignment: .leading, spacing: 4) {
                    if data.completed { Text("Cut finished").font(.largeTitle.weight(.semibold)) }
                    else { MetricValue("\(time.remaining)", unit: time.remaining == 1 ? "day left" : "days left", size: 58) }
                    if let finish = data.finish {
                        Text((data.completed ? "Ended " : "Ends ") + dateLabel(finish))
                            .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                    }
                }.accessibilityElement(children: .combine).accessibilityIdentifier("cutDaysRemaining")
                progress("Time", value: time.fraction.formatted(.percent.precision(.fractionLength(0))), fraction: time.fraction)
            }
            if let loss = data.summary.progress?.totalLostKg {
                let value = WeeklyWeightPresentation.weight(abs(loss), unit: unit)
                if let planned = data.plannedLoss, loss >= 0 {
                    progress("Weight", value: "\(value) / \(WeeklyWeightPresentation.weight(planned, unit: unit)) \(unit) lost", fraction: data.weightFraction)
                } else {
                    progress("Weight", value: "\(value) \(unit) \(loss < 0 ? "gained" : "lost")", fraction: data.weightFraction)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("cutProgress")
    }
    private func dateLabel(_ date: Date) -> String {
        var format = Date.FormatStyle().day().month(.abbreviated); format.timeZone = data.calendar.timeZone
        return date.formatted(format)
    }
    private func progress(_ label: String, value: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack { Text(label); Spacer(); Text(value).monospacedDigit() }
                VStack(alignment: .leading, spacing: 4) { Text(label); Text(value).monospacedDigit() }
            }.font(.subheadline)
            if let fraction {
                GeometryReader { geometry in
                    Capsule().fill(SnoopStyle.separator)
                        .overlay(alignment: .leading) { Capsule().fill(SnoopStyle.load).frame(width: geometry.size.width * fraction) }
                }.frame(height: 7).accessibilityHidden(true)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityValue(value)
    }
}
