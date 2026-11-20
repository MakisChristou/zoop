import SwiftUI

/// The live sensor and second clock invalidate only the small readout, not the chart.
struct DayTimelineReadout: View {
    let value: Double?
    let unit: String
    let date: Date?
    let liveHeartRate: Bool
    let decimals: Int
    @Environment(AppModel.self) private var model
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fresh = liveHeartRate && model.strap.state == .ready && model.strap.realtimeStreaming
                && model.strap.liveUpdatedAt.map { context.date.timeIntervalSince($0) >= 0 && context.date.timeIntervalSince($0) < 5 } == true
                && model.strap.smoothedHeartRate != nil
            let reading = fresh ? model.strap.smoothedHeartRate.map(Double.init) : value
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(reading.map { $0.formatted(.number.precision(.fractionLength(decimals))) } ?? "—")
                    .font(ZoopType.font(size: 16, weight: .medium, relativeTo: .body)).monospacedDigit()
                Text(unit).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                if fresh {
                    Circle().fill(ZoopStyle.favourable).frame(width: 5, height: 5).accessibilityHidden(true)
                    Text("Live").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                } else if let date {
                    Text(date, format: .dateTime.hour().minute()).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                }
            }.accessibilityElement(children: .combine)
        }
    }
}
