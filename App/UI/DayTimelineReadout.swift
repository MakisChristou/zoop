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
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            // A sensor update can render between scheduled ticks. Use the actual
            // render time; the previous tick can predate a newly received sample.
            let reading = TimelineReading.resolve(value: value, date: date, wantsLive: liveHeartRate,
                                                  sensorValue: model.strap.smoothedHeartRate,
                                                  sensorDate: model.strap.liveUpdatedAt,
                                                  streaming: model.strap.state == .ready && model.strap.realtimeStreaming)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(reading.value.map { $0.formatted(.number.precision(.fractionLength(decimals))) } ?? "—")
                    .font(ZoopType.font(size: 16, weight: .medium, relativeTo: .body)).monospacedDigit()
                Text(unit).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                if reading.isLive {
                    Circle().fill(ZoopStyle.favourable).frame(width: 5, height: 5).accessibilityHidden(true)
                    Text("Live").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                } else if let date = reading.date {
                    Text(date, format: .dateTime.hour().minute()).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                }
            }.accessibilityElement(children: .combine)
        }
    }
}
