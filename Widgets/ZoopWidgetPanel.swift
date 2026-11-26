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
        data.steps = 8_000
        data.stepsGoal = 10_000
        data.latestKg = 63.8
        return ZoopWidgetEntry(date: now, data: data)
    }
}
enum ZoopWidgetKind: String {
    case today = "Today", recovery = "Recovery", weight = "Weight", steps = "Steps"
    var family: WidgetFamily { self == .recovery || self == .steps ? .systemSmall : .systemMedium }
    var detail: String {
        switch self {
        case .today: "Sleep, recovery and load."
        case .recovery: "Your recovery over the last week."
        case .weight: "Your weight trend and weekly check-ins."
        case .steps: "Today’s steps and progress toward your goal."
        }
    }
}
struct ZoopWidgetPanel: View {
    let kind: ZoopWidgetKind
    let entry: ZoopWidgetEntry
    private var data: WidgetSnapshot { entry.data }
    private let sleep = Color(red: 0.51, green: 0.58, blue: 0.86)
    private let blue = Color(red: 0.28, green: 0.62, blue: 0.92)
    private let calendar = Calendar.current
    private var reference: Date { data.day ?? entry.date }
    private var todayScore: WidgetSnapshot.Recovery? {
        data.recovery.first { calendar.isDate($0.day, inSameDayAs: reference) }
    }
    private func tone(_ band: String?) -> Color {
        switch band { case "high": .green; case "moderate": .yellow; case "low": .red; default: .secondary }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kind.rawValue).font(.subheadline.weight(.medium))
                Spacer(minLength: 2)
                if kind == .weight {
                    Text(data.latestKg.map { (data.unit == "lb" ? $0 * 2.2046226218 : $0).formatted(.number.precision(.fractionLength(1))) + " " + data.unit } ?? "—")
                        .font(.headline)
                } else if kind != .steps, let date = data.day, !calendar.isDate(date, inSameDayAs: entry.date) {
                    Text(date, format: .dateTime.day().month(.abbreviated)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            switch kind {
            case .today:
                HStack(spacing: 12) {
                    ring("Sleep", data.sleepSeconds.map { "\($0 / 3600)h \(($0 % 3600) / 60)m" }, data.sleepFraction, sleep)
                    ring("Recovery", todayScore?.score.map { "\($0)%" }, todayScore?.score.map { Double($0)/100 }, tone(todayScore?.band))
                    ring("Load", data.load?.formatted(.number.precision(.fractionLength(1))), data.loadFraction, blue)
                }.frame(maxHeight: .infinity)
            case .recovery:
                Text(todayScore?.score.map { "\($0)%" } ?? "—").font(.system(size: 34, weight: .semibold)).minimumScaleFactor(0.7)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(-6..<1, id: \.self) { offset in
                        let date = calendar.date(byAdding: .day, value: offset, to: reference)!
                        let reading = data.recovery.first { calendar.isDate($0.day, inSameDayAs: date) }
                        GeometryReader { size in
                            if let score = reading?.score {
                                RoundedRectangle(cornerRadius: 2).fill(tone(reading?.band)).widgetAccentable()
                                    .frame(height: max(1, size.size.height * CGFloat(score)/100))
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }.accessibilityLabel(date.formatted(date: .abbreviated, time: .omitted) + ", " + (reading?.score.map { "\($0) percent" } ?? "No score"))
                    }
                }
            case .steps:
                let reading = data.stepsReading(on: entry.date)
                ZStack {
                    Circle().strokeBorder(.gray.opacity(0.35), lineWidth: 4)
                    if let fraction = reading?.fraction, fraction > 0 {
                        Circle().inset(by: 2).trim(from: 0, to: fraction)
                            .stroke(blue, style: .init(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90)).widgetAccentable()
                    }
                    Text(reading?.count.formatted() ?? "—")
                        .font(.system(size: 25, weight: .semibold)).monospacedDigit()
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
                Chart(data.weights, id: \.day) { point in
                    LineMark(x: .value("Date", point.day), y: .value("Weight in kg", point.kg), series: .value("Segment", point.segment))
                    PointMark(x: .value("Date", point.day), y: .value("Weight in kg", point.kg))
                        .symbolSize(point.day == data.weights.last?.day || data.weights.filter { $0.segment == point.segment }.count == 1 ? 12 : 0)
                }.chartYScale(domain: .automatic(includesZero: false)).chartXAxis(.hidden).chartYAxis(.hidden)
                    .foregroundStyle(.primary).padding(.vertical, 4)
                HStack {
                    ForEach(0..<7) { offset in
                        let start = calendar.dateInterval(of: .weekOfYear, for: entry.date)!.start
                        let day = calendar.date(byAdding: .day, value: offset, to: start)!
                        let logged = data.weights.contains { calendar.isDate($0.day, inSameDayAs: day) }
                        VStack(spacing: 3) {
                            Circle().fill(logged ? Color.green : .clear)
                                .overlay { Circle().stroke(logged ? .clear : .secondary, lineWidth: 1) }
                                .overlay { if calendar.isDate(day, inSameDayAs: entry.date) { Circle().stroke().padding(-2) } }
                                .frame(width: 8, height: 8)
                            Text(day, format: .dateTime.weekday(.narrow)).font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide)) + (logged ? ", logged" : ", no weigh-in"))
                    }
                }
            }
        }.foregroundStyle(.primary).environment(\.colorScheme, .dark)
    }

    private func ring(_ label: String, _ value: String?, _ fraction: Double?, _ color: Color) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(.gray.opacity(0.35), lineWidth: 4)
                Circle().trim(from: 0, to: min(max(fraction ?? 0, 0), 1))
                    .stroke(color, style: .init(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90)).widgetAccentable()
                Text(value ?? "—").font(.headline).minimumScaleFactor(0.6).lineLimit(1).padding(5)
            }.aspectRatio(1, contentMode: .fit)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore).accessibilityLabel(label + ", " + (value ?? "No reading"))
    }
}
