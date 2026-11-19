import SwiftUI

/// Only the live values observe incoming sensor readings and the second clock.
struct TodayLiveMetric: View {
    enum Kind { case heartRate, temperature }
    let kind: Kind
    let isViewingToday: Bool
    let summary: ZoopAPI.Day?
    let history: [Double]
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
    }
    @ViewBuilder private func content(now: Date) -> some View {
        if kind == .heartRate { heartRate(now: now) }
        else {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 20))
            layout {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Skin temperature").font(.caption.weight(.medium)).foregroundStyle(ZoopStyle.secondary)
                    MetricValue(skinTemperature.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "°C", size: 28)
                    Text(isViewingToday ? freshness(now: now) : "Day average").font(.caption).foregroundStyle(ZoopStyle.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Sparkline(values: history, color: ZoopStyle.temperature)
                    .frame(width: typeSize.isAccessibilitySize ? nil : 110, height: 32).accessibilityHidden(true)
            }.zoopCard().accessibilityElement(children: .combine)
        }
    }
    private func heartRate(now: Date) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Label(isViewingToday ? "Heart rate" : "Average heart rate", systemImage: "heart")
                .font(.subheadline).foregroundStyle(ZoopStyle.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(heartRateValue).font(.title3.weight(.semibold)).monospacedDigit()
                Text("bpm").font(.caption).foregroundStyle(ZoopStyle.secondary)
                Text(isViewingToday ? freshness(now: now) : "Day average").font(.caption).foregroundStyle(ZoopStyle.secondary).padding(.leading, 4)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var heartRateValue: String {
        if isViewingToday { return model.strap.smoothedHeartRate.map(String.init) ?? "—" }
        return summary?.hrAvg.map { String(Int($0.rounded())) } ?? "—"
    }

    private var skinTemperature: Double? {
        isViewingToday ? model.strap.lastBiometric?.skinTemperatureC.map(Double.init) : summary?.skinTempAvg
    }

    private func freshness(now: Date) -> String {
        guard let at = model.strap.liveUpdatedAt else { return "No reading" }
        let age = Int(now.timeIntervalSince(at))
        if model.strap.state == .ready, model.strap.realtimeStreaming, age < 5 { return "Live" }
        return age < 60 ? "\(max(0, age))s ago" : "\(age / 60)m ago"
    }
}
