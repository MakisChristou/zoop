import SwiftUI

/// Backend-owned nightly readings, presented without the live temperature/chart mix.
struct TodayHealthMetrics: View {
    let insights: MorningInsights?
    let physiology: ZoopAPI.Night.Physiology?
    let day: Date
    let isToday: Bool
    let isLoading: Bool
    let openSleep: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Kind: String, CaseIterable {
        case hrv, restingHR, breathing, oxygen, temperature
        var title: String {
            switch self {
            case .hrv: "HRV"
            case .restingHR: "Resting HR"
            case .breathing: "Breathing"
            case .oxygen: "SpO₂"
            case .temperature: "Skin temperature"
            }
        }
        var unit: String {
            switch self {
            case .hrv: "ms"
            case .restingHR: "bpm"
            case .breathing: "/min"
            case .oxygen: "%"
            case .temperature: "°C"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let header = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(spacing: 12))
            header {
                Text("Health").font(ZoopStyle.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                if !typeSize.isAccessibilitySize {
                    Rectangle().fill(ZoopStyle.separator).frame(height: 0.5)
                }
                if isLoading {
                    ProgressView().controlSize(.mini).accessibilityLabel("Loading health readings")
                } else {
                    Text(isToday ? "Last night" : "Overnight").font(ZoopType.caption).fixedSize()
                }
            }.foregroundStyle(ZoopStyle.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                     count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                ForEach(Kind.allCases, id: \.self) { kind in
                    if kind == .hrv || kind == .restingHR {
                        NavigationLink { MorningInsightsView(day: day) } label: { tile(kind) }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens your nightly comparisons")
                            .accessibilityIdentifier("todayHealth-\(kind.rawValue)")
                    } else {
                        Button(action: openSleep) { tile(kind) }
                            .buttonStyle(.plain).disabled(physiology == nil)
                            .accessibilityHint("Opens this night in Sleep")
                            .accessibilityIdentifier("todayHealth-\(kind.rawValue)")
                    }
                }
            }
        }
    }

    private func cardiac(_ kind: Kind) -> TodayCardiacReading {
        TodayCardiacReading(key: kind == .hrv ? "hrv" : "resting_hr",
                            insights: insights, physiology: physiology)
    }

    private func reading(_ kind: Kind) -> Double? {
        let value: Double?
        switch kind {
        // Keep the same server metric definitions and comparisons as Outlook.
        case .hrv, .restingHR: value = cardiac(kind).value
        case .breathing: value = physiology?.respiratoryRate
        case .oxygen: value = (physiology?.spo2Windows ?? 0) > 0 ? physiology?.spo2Pct : nil
        case .temperature: value = physiology?.skinTempC
        }
        guard let value, value.isFinite else { return nil }
        return value
    }

    private func tile(_ kind: Kind) -> some View {
        let value = reading(kind)
        let metric = kind == .hrv || kind == .restingHR ? cardiac(kind).metric : nil
        let delta = value == nil ? nil : metric?.visibleDelta
        let decimals = kind == .breathing || kind == .temperature ? 1 : 0
        return VStack(alignment: .leading, spacing: 10) {
            Text(kind.title).font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            MetricValue(value.map { $0.formatted(.number.precision(.fractionLength(decimals))) } ?? "—",
                        unit: kind.unit, size: 24)
                .fixedSize(horizontal: false, vertical: true)
            Text(delta ?? " ").font(ZoopType.caption).monospacedDigit()
                .foregroundStyle(InsightTone.color(metric?.comparison?.signal))
                .accessibilityHidden(delta == nil)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .zoopCard(padding: 16)
        .overlay { RoundedRectangle(cornerRadius: ZoopStyle.radius).strokeBorder(ZoopStyle.separator.opacity(0.6), lineWidth: 0.5) }
        .foregroundStyle(ZoopStyle.text)
        .accessibilityElement(children: .combine)
    }
}
