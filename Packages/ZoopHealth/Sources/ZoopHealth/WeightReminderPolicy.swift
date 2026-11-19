import Foundation

public enum WeightReminderPolicy {
    public static let delay: TimeInterval = 5 * 60
    public static let maximumWakeAge: TimeInterval = 3 * 60 * 60
    /// Wake must already have sustained-awake evidence from the server. Naps and
    /// edited/historical sessions never enter this policy. No time-of-day fallback.
    public static func delivery(now: Date, confirmedWake: Date?, enabledAt: Date?, hasWeight: Bool, alreadyReminded: Bool, calendar: Calendar = .current) -> Date? {
        guard let wake = confirmedWake, let enabledAt, !hasWeight, !alreadyReminded,
              wake >= enabledAt, wake <= now, now.timeIntervalSince(wake) <= maximumWakeAge,
              calendar.isDate(wake, inSameDayAs: now) else { return nil }
        return now.addingTimeInterval(delay)
    }
}
