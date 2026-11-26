import Foundation
import ZoopData
import ZoopHealth

@MainActor
final class WidgetPublisher {
    private var lastRequest = Date.distantPast
    private var activeScope = ""
    private var request: Task<Void, Never>?

    func refresh(_ model: AppModel, force: Bool = false) {
        let device = model.dataDevice
        let connection = Settings.connectionID
        let scope = Settings.healthScope(device: device)
        if scope != activeScope {
            request?.cancel()
            activeScope = scope
            lastRequest = .distantPast
            if WidgetSnapshot.read().owner != scope { WidgetSnapshot.clear() }
        }
        guard !device.isEmpty, Settings.permitsDevice(device), Settings.isConfigured,
              force || Date().timeIntervalSince(lastRequest) > 300 else { return }
        lastRequest = Date()
        request?.cancel()
        request = Task {
            let now = Date(), calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            let from = calendar.date(byAdding: .day, value: -6, to: today)!
            async let nights = ZoopAPI.nights(deviceId: device, limit: 7, summary: true)
            async let days = ZoopAPI.days(deviceId: device, limit: 7)
            async let steps = ZoopAPI.steps(deviceId: device, day: today)
            async let goal = ZoopAPI.sleepGoal(deviceId: device)
            async let history = ZoopAPI.recoveryHistory(deviceId: device, from: from, to: today, timezone: calendar.timeZone.identifier)
            let (nightRows, dayRows, target, scores) = await (try? nights, try? days, try? goal, try? history)
            let stepDetails = try? await steps
            guard !Task.isCancelled, model.dataDevice == device, Settings.connectionID == connection,
                  calendar.isDateInToday(today) else { return }
            guard nightRows != nil || dayRows != nil || scores != nil || stepDetails != nil else { return }
            var value = WidgetSnapshot.read().scoped(to: scope)
            value.beginDay(today)
            if let nightRows {
                value.sleepSeconds = nightRows.first { calendar.isDate($0.metrics.window.offset, inSameDayAs: today) }?.metrics.window.asleepS
            }
            if let target { value.sleepFraction = value.sleepSeconds.map { SleepGoal(minutes: target.minutes).progress(asleepSeconds: $0) } }
            let dayKey = DayKey.string(today)
            let summary = dayRows?.first { $0.day == dayKey }
            if dayRows != nil || stepDetails != nil {
                value.steps = ZoopAPI.StepsDay.displayedCount(on: dayKey, details: stepDetails, summary: summary)
            }
            value.stepsGoal = model.weeklyWeight.stepsTarget(forScope: scope, on: today)
            if dayRows != nil {
                value.load = summary?.load
                value.loadFraction = value.load.map { $0 / LoadRing.maximum }
            }
            if let scores {
                value.recovery = scores.compactMap { row in
                    DayKey.date(row.day, timeZone: calendar.timeZone).map {
                        .init(day: $0, score: row.recovery.displayedScore, band: row.recovery.band)
                    }
                }
            }
            value.save()
        }
    }

    func updateStepsGoal(_ model: AppModel) {
        let scope = Settings.healthScope(device: model.dataDevice)
        var snapshot = WidgetSnapshot.read()
        guard !scope.isEmpty, snapshot.owner == scope, let day = snapshot.day, Calendar.current.isDateInToday(day) else { return }
        snapshot.stepsGoal = model.weeklyWeight.stepsTarget(forScope: scope, on: day)
        snapshot.save()
    }

    func weight(_ model: AppModel) {
        guard !model.dataDevice.isEmpty, model.health.reminderDevice == model.dataDevice,
              let scope = model.health.reminderScope else { return }
        var value = WidgetSnapshot.read().scoped(to: scope)
        let rows = model.health.rows
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        value.weights = WeightTrend(rows.filter { $0.measuredAt >= cutoff }).points.map { .init(day: $0.day, kg: $0.kg, segment: $0.segment) }
        value.latestKg = WeightCheckInSummary(rows).latest?.kg
        value.unit = UserDefaults.standard.string(forKey: "weightUnit") == "lb" ? "lb" : "kg"
        value.save()
    }
}
