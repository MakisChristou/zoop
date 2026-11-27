import Charts
import SwiftUI
import WidgetKit

struct ZoopWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetSnapshot

    static var sample: ZoopWidgetEntry {
        let now = Date(), calendar = Calendar.current
        var data = WidgetSnapshot(day: now, sleepSeconds: 27120, sleepFraction: 0.94, load: 10.4, loadFraction: 10.4/21)
        let scores = [67, 78, 55, 31, 44, 62, 78]
        for (i, score) in scores.enumerated() {
            let date = calendar.date(byAdding: .day, value: i - 6, to: now)!
            data.recovery.append(.init(day: date, score: score, band: score >= 67 ? "high" : score <= 33 ? "low" : "moderate"))
            data.weights.append(.init(day: date, kg: [64.4,64.2,64.3,64.1,64.0,63.9,63.8][i], segment: 0))
        }
        let heatDays = WidgetHistory.heatmapDays(through: now, calendar: calendar)
        var loads: [Date: Double] = [:]
        for (index, date) in heatDays.enumerated() where date <= now && index % 23 != 10 {
            loads[date] = Double((index * 17 + index / 3 * 7) % 23)
        }
        data.activity = .init(refreshed: now, zone: calendar.timeZone.identifier, loads: loads)
        let earlierScores: [Int?] = [78,73,55,61,69,84,88,72,64,38,31,51,68,77,82,73,nil,81,90,66,52,49,72]
        for (index, score) in earlierScores.enumerated() {
            guard let score else { continue }
            let day = calendar.date(byAdding: .day, value: index - 29, to: now)!
            data.recovery.append(.init(day: day, score: score, band: score >= 67 ? "high" : score <= 33 ? "low" : "moderate"))
        }
        data.night = .init(end: now, asleepSeconds: 27120, stages: .init(deep: 5520, rem: 6480, light: 15120, awake: 1680),
                           restingHR: 48, hrv: 81, efficiency: 92, breathing: 13.2, partial: false)
        data.workouts = [
            .init(id: 1, start: now, name: "Strength training", icon: "dumbbell.fill", duration: 3060, load: 9.3),
            .init(id: 2, start: calendar.date(byAdding: .day, value: -1, to: now)!, name: "Walk", icon: "figure.walk", duration: 2520, load: 5.8)
        ]
        data.steps = 8_000
        data.stepsGoal = 10_000
        data.latestKg = 63.8
        return ZoopWidgetEntry(date: now, data: data)
    }
}
enum ZoopWidgetKind: String {
    case today = "Today", recovery = "Recovery", weight = "Weight", steps = "Steps", everyDay = "Every day"
    case stages = "Sleep stages", workouts = "Recent activities", metrics = "Nightly metrics"
    var family: WidgetFamily { self == .recovery || self == .steps ? .systemSmall : .systemMedium }
    var families: [WidgetFamily] { self == .recovery ? [.systemSmall, .systemMedium] : [family] }
    var detail: String {
        switch self {
        case .stages: "Your latest night of sleep by stage."
        case .workouts: "Your two most recent workouts."
        case .metrics: "Resting heart rate, HRV, efficiency and breathing during sleep."
        case .today: "Sleep, recovery and load."
        case .recovery: "Your daily recovery over a week or a month."
        case .everyDay: "Your daily load over the past 20 weeks."
        case .weight: "Your weight trend and weekly check-ins."
        case .steps: "Today’s steps and progress toward your goal."
        }
    }
}
struct ZoopWidgetPanel: View {
    let kind: ZoopWidgetKind
    let entry: ZoopWidgetEntry
    let family: WidgetFamily
    private var data: WidgetSnapshot { entry.data }
    private let sleep = Color(red: 0.51, green: 0.58, blue: 0.86)
    private let blue = Color(red: 0.28, green: 0.62, blue: 0.92)
    private let calendar = Calendar.current
    private var reference: Date { data.day ?? entry.date }
    private var todayScore: WidgetSnapshot.Recovery? {
        data.recovery.first { calendar.isDate($0.day, inSameDayAs: reference) }
    }
    var body: some View {
        if kind == .everyDay {
            WidgetHistoryPanel(entry: entry)
        } else if kind == .recovery {
            WidgetRecoveryPanel(entry: entry, wide: family == .systemMedium)
        } else if kind == .stages || kind == .workouts || kind == .metrics {
            WidgetDetailsPanel(kind: kind, entry: entry)
        } else {
            compactPanel
        }
    }
    private var compactPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if kind == .today, let date = data.day, !calendar.isDate(date, inSameDayAs: entry.date) {
                Text(date, format: .dateTime.day().month(.abbreviated))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            switch kind {
            case .today:
                HStack(spacing: 12) {
                    ring("Sleep", icon: "moon", data.sleepSeconds.map { "\($0 / 3600)h \(($0 % 3600) / 60)m" }, data.sleepFraction, sleep)
                    ring("Recovery", icon: "heart", todayScore?.score.map { "\($0)%" }, todayScore?.score.map { Double($0)/100 }, todayScore?.widgetColor ?? .secondary)
                    ring("Load", icon: "bolt", data.load?.formatted(.number.precision(.fractionLength(1))), data.loadFraction, blue)
                }.frame(maxHeight: .infinity)
            case .recovery, .everyDay, .stages, .workouts, .metrics:
                EmptyView()
            case .steps:
                let reading = data.stepsReading(on: entry.date)
                ZStack {
                    Circle().strokeBorder(.gray.opacity(0.35), lineWidth: 5)
                    if let fraction = reading?.fraction, fraction > 0 {
                        Circle().inset(by: 2.5).trim(from: 0, to: fraction)
                            .stroke(blue, style: .init(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90)).widgetAccentable()
                    }
                    Text(reading?.count.formatted(.number.grouping(.never)) ?? "—")
                        .font(.system(size: 32, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6).padding(8)
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Steps")
                .accessibilityValue(reading.map { reading in
                    reading.count.formatted() + (reading.goal.map { " of " + $0.formatted() } ?? "")
                } ?? "No reading")
            case .weight:
                if let kg = data.latestKg {
                    let value = displayWeight(kg)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value.formatted(.number.precision(.fractionLength(1)))).font(.title.bold())
                        Text(data.unit).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Weight, \(value.formatted(.number.precision(.fractionLength(1)))) \(data.unit)")
                } else {
                    Text("—").font(.title.bold()).accessibilityLabel("No weigh-in")
                }
                Chart {
                    if !data.weights.isEmpty, let latest = data.latestKg {
                        RuleMark(y: .value("Latest weight (\(data.unit))", displayWeight(latest)))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    ForEach(data.weights, id: \.day) { point in
                        LineMark(x: .value("Date", point.day), y: .value("Weight (\(data.unit))", displayWeight(point.kg)), series: .value("Segment", point.segment))
                        PointMark(x: .value("Date", point.day), y: .value("Weight (\(data.unit))", displayWeight(point.kg)))
                            .symbolSize(point.day == data.weights.last?.day || data.weights.filter { $0.segment == point.segment }.count == 1 ? 12 : 0)
                    }
                }.chartYScale(domain: .automatic(includesZero: false)).chartXAxis(.hidden).chartYAxis(.hidden)
                    .foregroundStyle(.primary).padding(.vertical, 4)
                HStack(spacing: 0) {
                    ForEach(0..<7) { offset in
                        let start = calendar.dateInterval(of: .weekOfYear, for: entry.date)!.start
                        let day = calendar.date(byAdding: .day, value: offset, to: start)!
                        let logged = data.weights.contains { calendar.isDate($0.day, inSameDayAs: day) }
                        if offset > 0 { Spacer(minLength: 0) }
                        let isToday = calendar.isDate(day, inSameDayAs: entry.date)
                        VStack(spacing: 2) {
                            Circle().fill(logged ? Color.green : .clear)
                                .overlay { Circle().stroke(logged ? .clear : .secondary, lineWidth: 1) }
                                .overlay { if isToday { Circle().stroke(logged ? Color.green : .primary, lineWidth: 1.5).padding(-2.5) } }
                                .frame(width: 7, height: 7).padding(3)
                            Text(day, format: .dateTime.weekday(.narrow))
                                .font(.caption2).foregroundStyle(isToday ? .primary : .secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel((isToday ? "Today, " : "") + day.formatted(.dateTime.weekday(.wide)) + (logged ? ", logged" : ", no weigh-in"))
                    }
                }
            }
        }.foregroundStyle(.primary).environment(\.colorScheme, .dark)
    }

    private func displayWeight(_ kg: Double) -> Double {
        data.unit == "lb" ? kg * 2.2046226218 : kg
    }

    private func ring(_ label: String, icon: String, _ value: String?, _ fraction: Double?, _ color: Color) -> some View {
        ZStack {
            Circle().strokeBorder(.gray.opacity(0.35), lineWidth: 4)
            if let fraction, fraction > 0 {
                Circle().inset(by: 2).trim(from: 0, to: min(fraction, 1))
                    .stroke(color, style: .init(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90)).widgetAccentable()
            }
            VStack(spacing: 4) {
                Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
                Text(value ?? "—").font(.headline).minimumScaleFactor(0.6).lineLimit(1)
            }.padding(7)
        }
        .aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore).accessibilityLabel(label + ", " + (value ?? "No reading"))
    }
}

extension WidgetSnapshot.Recovery {
    var widgetColor: Color {
        switch band {
        case "high": Color(red: 0.278, green: 0.812, blue: 0.475)
        case "moderate": Color(red: 0.988, green: 0.769, blue: 0.278)
        case "low": Color(red: 0.969, green: 0.361, blue: 0.380)
        default: .secondary
        }
    }
}
