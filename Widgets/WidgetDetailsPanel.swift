import SwiftUI
import WidgetKit

struct WidgetDetailsPanel: View {
    let kind: ZoopWidgetKind
    let entry: ZoopWidgetEntry

    var body: some View {
        Group {
            if kind == .workouts {
                workouts
            } else if let night = entry.data.night {
                if kind == .metrics { metrics(night) } else { stages(night) }
            } else { empty("No night recorded yet") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.primary).environment(\.colorScheme, .dark)
        .widgetURL(URL(string: kind == .workouts ? "zoop://widget/activity" : "zoop://widget/sleep"))
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
    }

    private func duration(_ seconds: Int) -> String {
        let minutes = Int((Double(max(0, seconds)) / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private func dateLabel(_ date: Date, night: Bool = false) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: entry.date) { return night ? "Last night" : "Today" }
        if !night, let yesterday = calendar.date(byAdding: .day, value: -1, to: entry.date),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    @ViewBuilder private func stages(_ night: WidgetSnapshot.Night) -> some View {
        if let stages = night.stages {
            let items: [(String, Int, Color)] = [
                ("Deep", stages.deep, Color(red: 129/255, green: 148/255, blue: 220/255)),
                ("REM", stages.rem, Color(red: 85/255, green: 95/255, blue: 137/255)),
                ("Light", stages.light, Color(red: 51/255, green: 57/255, blue: 77/255)),
                ("Awake", stages.awake, Color(white: 59/255))
            ]
            VStack(alignment: .leading) {
                HStack(alignment: .firstTextBaseline) {
                    Text(duration(night.asleepSeconds)).font(.title.weight(.semibold))
                    Spacer()
                    Text((night.partial ? "Partial · " : "") + dateLabel(night.end, night: true))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                GeometryReader { geometry in
                    let visible = items.filter { $0.1 > 0 }
                    let total = visible.reduce(0) { $0 + $1.1 }
                    let width = max(0, geometry.size.width - CGFloat(max(0, visible.count - 1)) * 2)
                    HStack(spacing: 2) {
                        ForEach(visible, id: \.0) { item in
                            RoundedRectangle(cornerRadius: 2).fill(item.2)
                                .frame(width: width * CGFloat(item.1) / CGFloat(total))
                        }
                    }
                }.frame(height: 11).accessibilityHidden(true)
                Spacer()
                HStack(spacing: 3) {
                    ForEach(items, id: \.0) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Circle().fill(item.2).frame(width: 6, height: 6)
                                Text(item.0).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(duration(item.1)).font(.subheadline.weight(.medium))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                    }
                }
            }
        } else { empty("No sleep stages recorded") }
    }

    private func metrics(_ night: WidgetSnapshot.Night) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if night.partial || !Calendar.current.isDate(night.end, inSameDayAs: entry.date) {
                Text((night.partial ? "Partial · " : "") + dateLabel(night.end, night: true))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                metric("Resting HR", night.restingHR, "bpm")
                metric("HRV", night.hrv, "ms")
            }
            Divider()
            HStack {
                metric("Efficiency", night.efficiency, "%")
                metric("Breathing", night.breathing, "/ min", digits: 1)
            }
        }
    }

    private func metric(_ title: String, _ value: Double?, _ unit: String, digits: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value?.formatted(.number.precision(.fractionLength(digits))) ?? "—").font(.title2.weight(.semibold))
                if value != nil { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var workouts: some View {
        if let rows = entry.data.workouts, !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(rows.prefix(2)) { row in
                    HStack(spacing: 9) {
                        Image(systemName: row.icon).frame(width: 31, height: 31)
                            .overlay { Circle().stroke(.quaternary) }
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.85)
                            Text(dateLabel(row.start) + " · " + duration(row.duration)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 2)
                        if let load = row.load {
                            Capsule().fill(.quaternary).frame(width: 37, height: 5)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color(red: 71/255, green: 158/255, blue: 234/255))
                                        .frame(width: 37 * min(1, max(0, load / 21)))
                                }.accessibilityHidden(true)
                        }
                        Text(row.load?.formatted(.number.precision(.fractionLength(1))) ?? "—")
                            .font(.subheadline.weight(.medium)).monospacedDigit()
                    }.frame(maxHeight: .infinity).accessibilityElement(children: .combine)
                }
            }.background(alignment: .leading) {
                if rows.count > 1 {
                    GeometryReader { geometry in
                        Rectangle().fill(.quaternary).frame(width: 1, height: max(0, geometry.size.height / 2 - 31))
                            .position(x: 15.5, y: geometry.size.height / 2)
                    }.accessibilityHidden(true)
                }
            }
        } else { empty("No recent activities") }
    }
}
