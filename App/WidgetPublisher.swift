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
            let from = calendar.date(byAdding: .day, value: 1 - WidgetHistory.recoveryDays, to: today)!
            let cached = WidgetSnapshot.read().scoped(to: scope).activity
            let fullHistory = cached?.isFresh(on: today, calendar: calendar) != true
            let dayLimit = fullHistory ? WidgetHistory.weeks * 7 : 7
            async let nights = ZoopAPI.nights(deviceId: device, limit: 7, summary: true)
            let weekStart = calendar.date(byAdding: .day, value: -7, to: today)!
            async let sessions = ZoopAPI.sleepSessions(deviceId: device, from: weekStart, to: now)
            async let workouts = ZoopAPI.workouts(deviceId: device, limit: 8, to: now)
            async let days = ZoopAPI.days(deviceId: device, limit: dayLimit)
            async let steps = ZoopAPI.steps(deviceId: device, day: today)
            async let goal = ZoopAPI.sleepGoal(deviceId: device)
            async let history = ZoopAPI.recoveryHistory(deviceId: device, from: from, to: today, timezone: calendar.timeZone.identifier)
            let (nightRows, dayRows, target, scores) = await (try? nights, try? days, try? goal, try? history)
            let (stepDetails, sleepRows, workoutRows) = await (try? steps, try? sessions, try? workouts)
            guard !Task.isCancelled, model.dataDevice == device, Settings.connectionID == connection,
                  Settings.healthScope(device: device) == scope, calendar.isDateInToday(today) else { return }
            guard nightRows != nil || dayRows != nil || scores != nil || stepDetails != nil || sleepRows != nil || workoutRows != nil else { return }
            var value = WidgetSnapshot.read().scoped(to: scope)
            value.beginDay(today)
            if let sleepRows {
                let main = Self.primaryNight(sleepRows, endingBy: now, calendar: calendar)
                value.night = main.flatMap(Self.night)
            }
            if let workoutRows {
                value.workouts = workoutRows.filter { $0.endTs <= now && $0.metricsPending != true }.prefix(2).map { row in
                    let kind = ActivityKind.named(row.kind)
                    return .init(id: row.id, start: row.startTs, name: kind.name, icon: kind.icon,
                                 duration: row.durationS, load: row.load)
                }
            }
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
            if let dayRows {
                let dated = dayRows.compactMap { row in
                    DayKey.date(row.day, timeZone: calendar.timeZone).map { ($0, row.load) }
                }
                let oldest = dated.map(\.0).min() ?? today
                var loads = fullHistory || dayRows.count < dayLimit ? [:] : (cached?.loads ?? [:]).filter { $0.key < oldest }
                let firstDay = WidgetHistory.heatmapDays(through: today, calendar: calendar)[0]
                for (date, load) in dated where date >= firstDay && date <= today {
                    loads[date] = load
                }
                value.activity = .init(refreshed: today, zone: calendar.timeZone.identifier, loads: loads)
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

    /// On the latest wake date, use the dashboard's fixed / longest / lowest-ID order.
    static func primaryNight(_ sessions: [ZoopAPI.SleepSession], endingBy now: Date, calendar: Calendar) -> ZoopAPI.SleepSession? {
        let main = sessions.filter { $0.isActive && $0.kind == "main" && $0.endTs <= now }
        guard let end = main.map(\.endTs).max() else { return nil }
        return main.filter { calendar.isDate($0.endTs, inSameDayAs: end) }.min { lhs, rhs in
            if (lhs.fixed == true) != (rhs.fixed == true) { return lhs.fixed == true }
            if lhs.durationS != rhs.durationS { return lhs.durationS > rhs.durationS }
            return lhs.id < rhs.id
        }
    }

    static func night(_ session: ZoopAPI.SleepSession) -> WidgetSnapshot.Night? {
        guard !session.metricsPending, let sleep = session.sleep else { return nil }
        let partial = sleep.partial == true
        let physiology = sleep.physiology
        return .init(end: session.endTs, asleepSeconds: sleep.window.asleepS,
                     stages: sleep.stages.map { .init(deep: $0.deepS, rem: $0.remS, light: $0.lightS, awake: $0.wakeS) },
                     restingHR: physiology.restingHr, hrv: physiology.hrvRmssdMs,
                     efficiency: partial ? nil : sleep.window.efficiency * 100,
                     breathing: physiology.respiratoryRate, partial: partial)
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
