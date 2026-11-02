import SwiftUI

/// Only the live values observe incoming sensor readings and the second clock.
struct TodayLiveMetric: View {
    enum Kind { case heartRate, temperature }
    let kind: Kind
    let isViewingToday: Bool
    let summary: SnoopAPI.Day?
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
            Tile(title: "Skin temperature", value: skinTemperature.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "°C",
                 caption: isViewingToday ? freshness(now: now) : "Day average", history: history, color: SnoopStyle.temperature)
        }
    }
    private func heartRate(now: Date) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Label(isViewingToday ? "Heart rate" : "Average heart rate", systemImage: "heart")
                .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(heartRateValue).font(.title3.weight(.semibold)).monospacedDigit()
                Text("bpm").font(.caption).foregroundStyle(SnoopStyle.secondary)
                Text(isViewingToday ? freshness(now: now) : "Day average").font(.caption).foregroundStyle(SnoopStyle.secondary).padding(.leading, 4)
            }
        }
        .padding(.vertical, 10)
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
