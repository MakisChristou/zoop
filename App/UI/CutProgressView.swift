import SwiftUI

struct CutProgressView: View {
    let data: CutProgressData
    let unit: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 16))
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    if let loss = data.summary.progress?.totalLostKg {
                        MetricValue(WeeklyWeightPresentation.weight(abs(loss), unit: unit), unit: unit, size: 44)
                        Text(loss < 0 ? "Gained" : "Lost").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                    } else {
                        Text("No weigh-ins yet").font(.title2.weight(.semibold))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine).accessibilityIdentifier("cutWeightChange")
                if let time = data.time {
                    VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                        Text(data.completed ? "Cut finished" : "\(time.remaining) " + (time.remaining == 1 ? "day left" : "days left"))
                            .font(.headline).monospacedDigit()
                        if let finish = data.finish {
                            Text((data.completed ? "Ended " : "Ends ") + dateLabel(finish))
                                .font(.caption).foregroundStyle(SnoopStyle.secondary)
                        }
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("cutDaysRemaining")
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                if let target = data.summary.progress?.targetWeightKg {
                    progress("Weight", value: "Goal \(WeeklyWeightPresentation.weight(target, unit: unit)) \(unit)", fraction: data.weightFraction)
                }
                if let time = data.time {
                    progress("Time", value: time.fraction.formatted(.percent.precision(.fractionLength(0))), fraction: time.fraction)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("cutProgress")
    }
    private func dateLabel(_ date: Date) -> String {
        var format = Date.FormatStyle().day().month(.abbreviated); format.timeZone = data.calendar.timeZone
        return date.formatted(format)
    }
    private func progress(_ label: String, value: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack { Text(label); Spacer(); Text(value).monospacedDigit() }
                VStack(alignment: .leading, spacing: 4) { Text(label); Text(value).monospacedDigit() }
            }.font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            if let fraction {
                GeometryReader { geometry in
                    Capsule().fill(SnoopStyle.separator)
                        .overlay(alignment: .leading) { Capsule().fill(SnoopStyle.load).frame(width: geometry.size.width * fraction) }
                }.frame(height: 6).accessibilityHidden(true)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityValue(value)
    }
}
