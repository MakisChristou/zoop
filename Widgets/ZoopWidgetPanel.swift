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
        data.steps = 8_000
        data.stepsGoal = 10_000
        data.latestKg = 63.8
        return ZoopWidgetEntry(date: now, data: data)
    }
}
enum ZoopWidgetKind: String {
    case today = "Today", recovery = "Recovery", weight = "Weight", steps = "Steps", everyDay = "Every day"
    var family: WidgetFamily { self == .recovery || self == .steps ? .systemSmall : .systemMedium }
    var families: [WidgetFamily] { self == .recovery ? [.systemSmall, .systemMedium] : [family] }
    var detail: String {
        switch self {
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
        if kind == .everyDay || (kind == .recovery && family == .systemMedium) {
            WidgetHistoryPanel(entry: entry, isActivity: kind == .everyDay)
        } else {
            compactPanel
        }
    }
    private var compactPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if (kind == .today || kind == .recovery), let date = data.day, !calendar.isDate(date, inSameDayAs: entry.date) {
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
            case .recovery:
                Group {
                    if let score = todayScore?.score {
                        Text("\(score)\(Text("%").font(.title3.weight(.semibold)))")
                            .accessibilityLabel("Recovery, \(score) percent")
                    } else {
                        Text("—").accessibilityLabel("No recovery score")
                    }
                }.font(.system(size: 32, weight: .semibold)).minimumScaleFactor(0.7)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(-6..<1, id: \.self) { offset in
                        let date = calendar.date(byAdding: .day, value: offset, to: reference)!
                        let reading = data.recovery.first { calendar.isDate($0.day, inSameDayAs: date) }
                        GeometryReader { size in
                            if let score = reading?.score {
                                RoundedRectangle(cornerRadius: 2).fill(reading?.widgetColor ?? .secondary).widgetAccentable()
                                    .frame(height: max(1, size.size.height * CGFloat(score)/100))
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }.accessibilityLabel(date.formatted(date: .abbreviated, time: .omitted) + ", " + (reading?.score.map { "\($0) percent" } ?? "No score"))
                    }
                }
            case .everyDay:
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
                    Text(reading?.count.formatted() ?? "—")
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
                    let value = data.unit == "lb" ? kg * 2.2046226218 : kg
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value.formatted(.number.precision(.fractionLength(1)))).font(.title.bold())
                        Text(data.unit).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Weight, \(value.formatted(.number.precision(.fractionLength(1)))) \(data.unit)")
                } else {
                    Text("—").font(.title.bold()).accessibilityLabel("No weigh-in")
                }
                Chart(data.weights, id: \.day) { point in
                    LineMark(x: .value("Date", point.day), y: .value("Weight in kg", point.kg), series: .value("Segment", point.segment))
                    PointMark(x: .value("Date", point.day), y: .value("Weight in kg", point.kg))
                        .symbolSize(point.day == data.weights.last?.day || data.weights.filter { $0.segment == point.segment }.count == 1 ? 12 : 0)
                }.chartYScale(domain: .automatic(includesZero: false)).chartXAxis(.hidden).chartYAxis(.hidden)
                    .foregroundStyle(.primary).padding(.vertical, 4)
                HStack(spacing: 0) {
                    ForEach(0..<7) { offset in
                        let start = calendar.dateInterval(of: .weekOfYear, for: entry.date)!.start
                        let day = calendar.date(byAdding: .day, value: offset, to: start)!
                        let logged = data.weights.contains { calendar.isDate($0.day, inSameDayAs: day) }
                        if offset > 0 { Spacer(minLength: 0) }
                        let isToday = calendar.isDate(day, inSameDayAs: entry.date)
                        Circle().fill(logged ? Color.green : .clear)
                            .overlay { Circle().stroke(logged ? .clear : .secondary, lineWidth: 1) }
                            .overlay { if isToday { Circle().stroke(logged ? Color.green : .primary, lineWidth: 1.5).padding(-2.5) } }
                            .frame(width: 7, height: 7).padding(3)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel((isToday ? "Today, " : "") + day.formatted(.dateTime.weekday(.wide)) + (logged ? ", logged" : ", no weigh-in"))
                    }
                }
            }
        }.foregroundStyle(.primary).environment(\.colorScheme, .dark)
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
