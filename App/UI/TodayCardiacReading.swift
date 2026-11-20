import Foundation

/// A measurement can exist before its separate morning comparison is available.
struct TodayCardiacReading {
    let value: Double?
    let metric: MorningInsights.Metric?

    init(key: String, insights: MorningInsights?, physiology: ZoopAPI.Night.Physiology?) {
        let candidate = insights?.metrics.first { $0.key == key }
        let pending = insights?.state == "updating" || insights?.state == "awaiting_sync"
        if !pending, let candidate, let value = candidate.value, value.isFinite, value > 0 {
            self.value = value
            self.metric = candidate
        } else {
            let nightly: Double?
            switch key {
            case "hrv": nightly = (physiology?.hrvWindows ?? 0) > 0 ? physiology?.hrvRmssdMs : nil
            case "resting_hr": nightly = physiology?.restingHr
            default: nightly = nil
            }
            value = nightly.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            // Never attach a comparison for a different/stale value to the nightly fallback.
            metric = nil
        }
    }
}
