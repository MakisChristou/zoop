import Foundation

/// A personal display target, not an estimate of physiological sleep need.
struct SleepGoal {
    static let storageKey = "sleepGoalMinutes"
    static let defaultMinutes = 8 * 60
    static let choices = Array(stride(from: 60, through: 24 * 60, by: 15))
    let minutes: Int

    init(minutes: Int) {
        self.minutes = Self.choices.contains(minutes) ? minutes : Self.defaultMinutes
    }

    var title: String {
        minutes.isMultiple(of: 60) ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    func progress(asleepSeconds: Int?) -> Double {
        guard let asleepSeconds else { return 0 }
        return min(max(Double(asleepSeconds) / (Double(minutes) * 60), 0), 1)
    }

    func percentage(asleepSeconds: Int) -> String {
        progress(asleepSeconds: asleepSeconds).formatted(.percent.precision(.fractionLength(0)))
    }
}
