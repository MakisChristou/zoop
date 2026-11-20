import SwiftUI

struct GoalProgressCard: View {
    let data: CutProgressData
    let unit: String
    var endedAt: Date? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Progress").font(ZoopStyle.sectionTitle)
            if let loss = data.summary.progress?.totalLostKg {
                row(
                    loss < 0 ? "Weight gained" : "Weight lost", icon: "arrow.down.right",
                    badge: data.weightFraction.map {
                        $0.formatted(.percent.precision(.fractionLength(0)))
                    },
                    value: WeeklyWeightPresentation.weight(abs(loss), unit: unit) + " " + unit,
                    fraction: data.weightFraction)
            } else {
                Text("No weigh-ins").font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
            }
            if let time = data.time {
                row(
                    "Time", icon: "clock", badge: "\(time.elapsed) days",
                    value: time.fraction.formatted(.percent.precision(.fractionLength(0))),
                    fraction: time.fraction)
            }
            Divider().overlay(ZoopStyle.separator)
            let layout =
                typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                item("Start", weight: data.summary.progress?.startingWeightKg)
                item("Target", weight: data.summary.progress?.targetWeightKg)
                if let finish = data.finish {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Planned finish").font(ZoopType.caption).foregroundStyle(
                            ZoopStyle.secondary)
                        Text(date(finish)).font(
                            ZoopType.font(size: 16, weight: .medium, relativeTo: .body))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if endedAt != nil, data.time == nil {
                Text("\(max(0,data.days(data.start,data.today))) days").font(ZoopType.caption)
                    .foregroundStyle(ZoopStyle.secondary)
            }
        }.zoopCard().accessibilityElement(children: .contain).accessibilityIdentifier("cutProgress")
    }
    private func item(_ title: String, weight: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
            Text(
                WeeklyWeightPresentation.weight(weight, unit: unit)
                    + (weight == nil ? "" : " " + unit)
            )
            .font(ZoopType.font(size: 16, weight: .medium, relativeTo: .body)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func date(_ d: Date) -> String {
        var f = Date.FormatStyle().day().month(.abbreviated)
        f.timeZone = data.calendar.timeZone
        return d.formatted(f)
    }
    private func row(
        _ title: String, icon: String, badge: String?, value: String, fraction: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout =
                typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                Image(systemName: icon).foregroundStyle(ZoopStyle.secondary).frame(width: 18)
                    .accessibilityHidden(true)
                Text(title).font(ZoopType.subheadline)
                if let badge {
                    Text(badge).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(
                            ZoopStyle.track, in: Capsule())
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                Text(value).font(ZoopType.subheadline).monospacedDigit()
            }
            if let fraction {
                GeometryReader { geometry in
                    Capsule().fill(ZoopStyle.track).overlay(alignment: .leading) {
                        Capsule().fill(ZoopStyle.text).frame(
                            width: geometry.size.width * min(1, max(0, fraction)))
                    }
                }.frame(height: 6).padding(.leading, typeSize.isAccessibilitySize ? 0 : 28)
                    .accessibilityHidden(true)
            }
        }.accessibilityElement(children: .combine)
    }
}
