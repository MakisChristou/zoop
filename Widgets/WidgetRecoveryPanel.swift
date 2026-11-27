import SwiftUI

struct WidgetRecoveryPanel: View {
    let entry: ZoopWidgetEntry
    let wide: Bool

    var body: some View {
        let length = wide ? WidgetHistory.recoveryDays : 7
        let series = entry.data.recoverySpan(through: entry.date, count: length)
        let readings = series.compactMap { $0 }
        let current = readings.last.flatMap { Calendar.current.isDate($0.day, inSameDayAs: entry.date) ? $0 : nil }
        Group {
            if readings.isEmpty {
                Text("No scores yet").font(.subheadline).foregroundStyle(.secondary)
            } else if readings.count == 1, let only = readings.first {
                VStack(spacing: 4) {
                    percentage(only)
                    if current == nil { Text(only.day, format: .dateTime.month(.abbreviated).day()).font(.caption).foregroundStyle(.secondary) }
                }
            } else if wide && series.count <= 7 {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        percentage(current)
                        Text("\(readings.count) scores").font(.caption).foregroundStyle(.secondary)
                    }
                    bars(series)
                }.padding(.horizontal, 12)
            } else if wide {
                bars(series)
            } else {
                VStack(alignment: series.count < length ? .center : .leading, spacing: 6) {
                    percentage(current)
                    bars(series)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.colorScheme, .dark)
    }

    private func percentage(_ reading: WidgetSnapshot.Recovery?) -> some View {
        Group {
            if let score = reading?.score {
                Text("\(score)\(Text("%").font(.title3.weight(.semibold)))")
                    .accessibilityLabel("Recovery, \(score) percent")
            } else { Text("—").accessibilityLabel("No recovery score today") }
        }.font(.system(size: 32, weight: .semibold)).monospacedDigit()
    }

    private func bars(_ series: [WidgetSnapshot.Recovery?]) -> some View {
        Canvas { context, size in
            let pitch = min(size.width / CGFloat(series.count), wide && series.count <= 7 ? 28 : wide ? 17 : 22)
            let width = pitch * 0.74
            let start = (size.width - CGFloat(series.count) * pitch + pitch - width) / 2
            for (index, reading) in series.enumerated() {
                guard let reading, let score = reading.score else { continue }
                let height = max(1, size.height * CGFloat(min(100, max(0, score))) / 100)
                let rect = CGRect(x: start + CGFloat(index) * pitch, y: size.height - height, width: width, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: min(3, width / 3)), with: .color(reading.widgetColor))
            }
        }.accessibilityChildren {
            ForEach(series.compactMap { $0 }, id: \.day) { reading in
                Text("\(reading.day.formatted(date: .abbreviated, time: .omitted)), recovery \(reading.score ?? 0) percent")
            }
        }
    }
}
