import Foundation
import WidgetKit

/// Only display values cross the app-group boundary. Credentials stay in the app.
struct WidgetSnapshot: Codable, Equatable {
    struct Recovery: Codable, Equatable {
        let day: Date
        let score: Int?
        let band: String?
    }
    struct Weight: Codable, Equatable {
        let day: Date
        let kg: Double
        let segment: Int
    }
    var owner = ""
    var day: Date?
    var sleepSeconds: Int?
    var sleepFraction: Double?
    var load: Double?
    var loadFraction: Double?
    var steps: Int?
    var stepsGoal: Int?
    var recovery: [Recovery] = []
    var activity: ActivityHistory?
    var weights: [Weight] = []
    var latestKg: Double?
    var unit = "kg"

    func scoped(to scope: String) -> Self {
        owner == scope ? self : Self(owner: scope)
    }

    mutating func beginDay(_ today: Date) {
        guard day != today else { return }
        day = today
        sleepSeconds = nil
        sleepFraction = nil
        load = nil
        loadFraction = nil
        steps = nil
        stepsGoal = nil
    }

    func stepsReading(on date: Date, calendar: Calendar = .current) -> (count: Int, goal: Int?, fraction: Double?)? {
        guard let day, calendar.isDate(day, inSameDayAs: date), let steps, steps >= 0 else { return nil }
        let goal = stepsGoal.flatMap { $0 > 0 ? $0 : nil }
        return (steps, goal, goal.map { min(Double(steps) / Double($0), 1) })
    }

    private static var file: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "WidgetGroup") as? String else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("widget-values.json")
    }

    static func read() -> Self {
        guard let file, let bytes = try? Data(contentsOf: file),
              let value = try? JSONDecoder().decode(Self.self, from: bytes) else { return Self() }
        return value
    }

    static func clear() {
        if let file { try? FileManager.default.removeItem(at: file) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func save() {
        guard let file = Self.file, self != Self.read(), let data = try? JSONEncoder().encode(self) else { return }
        do {
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var resource = URLResourceValues()
            resource.isExcludedFromBackup = true
            var url = file
            try? url.setResourceValues(resource)
            WidgetCenter.shared.reloadAllTimelines()
        } catch { return }
    }
}
