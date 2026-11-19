import SwiftUI

enum WeeklyWeightPresentation {
    static func title(_ state: String) -> String {
        switch state { case "on_pace": "On pace"; case "slower_week": "Slower week"; case "faster_week": "Faster week"; case "below_pace": "Below target pace"; case "faster": "Faster than planned"; case "possible_stall": "Possible stall"; case "starting": "Starting"; case "unclear": "Trend unclear"; default: "More weigh-ins needed" }
    }
    static func color(_ state: String) -> Color {
        state == "on_pace" ? ZoopStyle.favourable : ["starting", "insufficient", "unclear"].contains(state) ? ZoopStyle.secondary : ZoopStyle.typical
    }
    static func reason(_ s: ZoopAPI.WeeklyWeightSummary) -> String {
        switch s.reason { case "within_target": "This week matches your target."; case "first_week": "Your first week is taking shape."; case "three_flat_weeks": "Your weekly median has held steady for three weeks."; case "two_slow_weeks": "Two weeks below your target pace."; case "two_fast_weeks": "Two weeks faster than your target pace."; case "one_slow_week": "A slower week. One week doesn’t make a stall."; case "one_fast_week": "A faster week. Watch the longer trend."; case "conflicting_weeks": "Recent weeks are moving in different directions."; default: "Keep logging to build your weekly comparison." }
    }
    static func weight(_ kg: Double?, unit: String, signed: Bool = false) -> String {
        guard let kg else { return "—" }
        let value = ((unit == "lb" ? kg * 2.2046226218 : kg) * 10).rounded() / 10
        return (signed && value > 0 ? "+" : value < 0 ? "−" : "") + abs(value).formatted(.number.precision(.fractionLength(1)))
    }
    static func date(_ key: String) -> Date? {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }
}
