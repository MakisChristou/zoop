import Charts
import SwiftUI

/// One day of steps: the walking count as the headline, the hourly chart, and the
/// walks. Tells loading, a failed request, a day with no strap data and a day with no
/// walking apart. Used for today on the Steps screen and for any day opened from a
/// comparison.
struct DaySteps: View {
    let day: Date
    /// The server's summary row for this day, when the days list has loaded.
    let summary: SnoopAPI.Day?
    /// Whether the days list has loaded, so a missing summary means "no data".
    let summariesLoaded: Bool
    let workouts: [SnoopAPI.Workout]

    @EnvironmentObject private var model: AppModel
    @State private var state: Loadable = .loading
    @State private var scrubHour: Int?

    enum Loadable {
        case loading
        case loaded(SnoopAPI.StepsDay)
        case failed(String)
    }

    private var noData: Bool { summariesLoaded && summary == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headline
            if noData {
                notice("No data for this day", systemImage: "sensor.tag.radiowaves.forward", detail: "The strap was not worn or has not synced it yet.")
            } else {
                switch state {
                case .loading: chartCard(nil)
                case let .loaded(data): chartCard(data)
                case let .failed(message):
                    notice("Could not load this day", systemImage: "wifi.exclamationmark", detail: message, retry: true)
                }
            }
            walks
        }
        .task(id: day) { await load() }
    }

    // MARK: - Headline

    private var loaded: SnoopAPI.StepsDay? {
        if case let .loaded(d) = state { return d }
        return nil
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(headlineValue)
                    .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text("steps").font(.title3).foregroundStyle(.secondary)
            }
            Text(headlineCaption).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var headlineValue: String {
        if noData { return "—" }
        switch state {
        case .loading: return summary?.stepsWalking.map { $0.formatted() } ?? "—"
        case let .loaded(d): return d.walking.formatted()
        case .failed: return summary?.stepsWalking.map { $0.formatted() } ?? "—"
        }
    }

    private var headlineCaption: String {
        if noData { return "while walking · nothing recorded" }
        var parts = ["while walking"]
        if let s = summary?.walkingS, s > 0 { parts.append("\(s / 60) min on foot") }
        if let d = loaded {
            if d.walking == 0 { parts.append("no walking recorded") }
            else { parts.append(d.bouts.count == 1 ? "1 walk" : "\(d.bouts.count) walks") }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Chart

    private struct Hour: Identifiable {
        let hour: Int
        let steps: Int
        var id: Int { hour }
    }

    private func hours(_ data: SnoopAPI.StepsDay?) -> [Hour] {
        (0..<24).map { h in Hour(hour: h, steps: data.map { h < $0.walkingHours.count ? $0.walkingHours[h] : 0 } ?? 0) }
    }

    private func chartCard(_ data: SnoopAPI.StepsDay?) -> some View {
        let hours = hours(data)
        let peak = hours.map(\.steps).max() ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("By hour").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                if let h = scrubHour, let hour = hours.first(where: { $0.hour == h }) {
                    Text("\(String(format: "%02d", h)):00 · \(hour.steps.formatted()) steps")
                        .font(.caption.weight(.semibold)).monospacedDigit()
                } else if data == nil {
                    Text("loading").font(.caption2).foregroundStyle(.tertiary)
                } else if peak > 0 {
                    Text("drag to inspect").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Chart(hours) { h in
                BarMark(x: .value("Hour", h.hour), y: .value("Steps", h.steps))
                    .foregroundStyle(scrubHour == h.hour ? Color.teal : Color.teal.opacity(scrubHour == nil ? 1 : 0.4))
                    .cornerRadius(2)
            }
            .chartXScale(domain: -0.5...23.5)
            .chartYScale(domain: 0...Double(max(peak, 100)))
            .chartXAxis { AxisMarks(values: [0, 6, 12, 18]) { v in AxisGridLine(); AxisValueLabel { Text("\(v.as(Int.self) ?? 0)h") } } }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .frame(height: 140)
            .opacity(data == nil ? 0.35 : 1)
            .overlay { if data == nil { ProgressView() } }
            .accessibilityLabel("Steps by hour")
            .accessibilityValue(data.map { "\($0.walking.formatted()) walking steps, busiest hour \(busiestHour(hours))" } ?? "loading")
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = value.location.x - geo[proxy.plotFrame!].origin.x
                                    scrubHour = proxy.value(atX: x, as: Double.self).map { Int($0.rounded()) }
                                }
                                .onEnded { _ in scrubHour = nil }
                        )
                }
            }
            if let d = data, d.walking == 0 {
                Text("No walking recorded. Short bursts of steps do not count; a walk is three minutes or more.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private func busiestHour(_ hours: [Hour]) -> String {
        guard let top = hours.max(by: { $0.steps < $1.steps }), top.steps > 0 else { return "none" }
        return "\(top.hour):00"
    }

    // MARK: - Notices

    private func notice(_ title: String, systemImage: String, detail: String, retry: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.headline)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
            if retry {
                Button("Retry") { Task { await load() } }
                    .buttonStyle(.bordered)
                    .font(.subheadline.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Walks

    @ViewBuilder
    private var walks: some View {
        if let d = loaded, !d.bouts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Walks").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                ForEach(d.bouts) { bout in
                    if let session = session(for: bout) {
                        NavigationLink(value: session) { WalkRow(bout: bout, linked: true) }
                            .buttonStyle(PressableCardStyle())
                    } else {
                        WalkRow(bout: bout, linked: false)
                    }
                }
            }
        }
    }

    /// The session a bout belongs to, when one covers at least half of it.
    private func session(for bout: SnoopAPI.StepsDay.Bout) -> SnoopAPI.Workout? {
        workouts.first { w in
            let overlap = min(w.endTs, bout.end).timeIntervalSince(max(w.startTs, bout.start))
            return overlap * 2 >= Double(bout.durationS)
        }
    }

    // MARK: - Data

    private func load() async {
        guard !model.strap.serial.isEmpty, Settings.isConfigured else {
            state = .failed("Set up the server connection under Profile → Advanced.")
            return
        }
        if case .failed = state { state = .loading }
        do {
            state = .loaded(try await SnoopAPI.steps(deviceId: model.strap.serial, day: day))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
