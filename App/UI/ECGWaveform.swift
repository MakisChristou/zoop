import SwiftUI

/// Native ADC values only. No invented sampling rate, voltage axis or diagnostic grid.
struct ECGWaveform: View {
    let samples: [Int32]
    var label = "Recorded signal"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(label).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
            Canvas { context, size in
                guard !samples.isEmpty else { return }
                let low = Double(samples.min() ?? 0), high = Double(samples.max() ?? 0)
                let range = max(high - low, 1), padding = size.height * 0.12
                var path = Path()
                // Min/max per pixel bucket preserves narrow peaks in longer recordings.
                let bucket = max(1, Int(ceil(Double(samples.count) / max(size.width, 1))))
                var points: [(Int, Int32)] = []
                for start in stride(from: 0, to: samples.count, by: bucket) {
                    let end = min(start + bucket, samples.count)
                    let indices = start..<end
                    if let minIndex = indices.min(by: { samples[$0] < samples[$1] }),
                       let maxIndex = indices.max(by: { samples[$0] < samples[$1] }) {
                        for i in Set([minIndex, maxIndex]).sorted() { points.append((i, samples[i])) }
                    }
                }
                for (offset, point) in points.enumerated() {
                    let x = Double(point.0) / Double(max(samples.count - 1, 1)) * size.width
                    let y = high == low ? size.height / 2 : padding + (1 - (Double(point.1) - low) / range) * (size.height - padding * 2)
                    if offset == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(ZoopStyle.heartRate), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
            .frame(height: 150)
            .accessibilityHidden(true)
            Text("Uncalibrated amplitude").font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
        }
        .zoopCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(samples.count) ECG samples. Amplitude and sample timing are not calibrated.")
    }
}
