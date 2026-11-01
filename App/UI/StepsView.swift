import Charts
import SwiftUI

/// Steps in depth, opened from Today's Steps tile. Day shows today by hour with its
/// walks; 7D and 30D compare days, and tapping one pushes that day's detail so the
/// chosen range is still there on the way back. Every number here is walking steps,
/// the same definition as the tile.
struct StepsView: View {
    enum Scope: String, CaseIterable, Identifiable, Hashable {
        case day = "Day", week = "7 days", month = "30 days"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
    }

    @EnvironmentObject private var model: AppModel
    private let initialDay: Date?
    @State private var scope: Scope
    @State private var days: Loadable = .loading
    @State private var refreshID = 0
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 190

    enum Loadable {
        case loading
        case loaded([SnoopAPI.Day])
        case failed(String)

        var rows: [SnoopAPI.Day] {
            if case let .loaded(rows) = self { return rows }
            return []
        }

        var isLoaded: Bool {
            if case .loaded = self { return true }
            return false
        }
    }

    init(initialScope: Scope = .day, day: Date? = nil) {
        _scope = State(initialValue: initialScope)
        initialDay = day
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Range", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Range")
                switch scope {
                case .day:
                    DaySteps(day: initialDay ?? today, summary: summary(for: initialDay ?? today), summariesLoaded: days.isLoaded, refreshID: refreshID)
                case .week, .month:
                    comparison
                }
            }
            .padding(.horizontal, SnoopStyle.gutter).padding(.vertical, 16)
        }
        .snoopScreen()
        .navigationTitle("Steps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(item: $selectedDay) { day in
            DayStepsView(day: day, summary: summary(for: day), summariesLoaded: days.isLoaded)
        }
        .onChange(of: model.activity.changeToken) { _, _ in Task { await load() } }
        .task(id: model.strap.serial) { await load() }
        .refreshable { await load(); refreshID += 1 }
        .onAppear {
            #if targetEnvironment(simulator)
            if UserDefaults.standard.string(forKey: "demoScreen") == "stepsday" {
                selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: today)
            }
            #endif
        }
    }

    // MARK: - Comparison

    private struct DayPoint: Identifiable {
        let date: Date
        let steps: Int?
        var id: Date { date }
    }

    private var points: [DayPoint] {
        let cal = Calendar.current
        let byDay = Dictionary(uniqueKeysWithValues: days.rows.compactMap { d in Self.day(d.day).map { ($0, d.stepsWalking) } })
        return (0..<scope.days).reversed().map { back in
            let date = cal.date(byAdding: .day, value: -back, to: today)!
            return DayPoint(date: date, steps: byDay[date] ?? nil)
        }
    }

    @ViewBuilder
    private var comparison: some View {
        let pts = points
        let with = pts.compactMap(\.steps)
        let average = with.isEmpty ? 0.0 : Double(with.reduce(0, +)) / Double(with.count)
        VStack(alignment: .leading, spacing: 6) {
            Text(scope == .week ? "Last 7 days" : "Last 30 days").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            MetricValue(days.isLoaded && !with.isEmpty ? Int(average.rounded()).formatted() : "—", size: 54)
            Text("Average steps per day").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            if days.isLoaded, !with.isEmpty {
                Text(comparisonCaption(with: with)).font(.caption).foregroundStyle(SnoopStyle.secondary)
            }
        }
        .accessibilityElement(children: .combine)

        switch days {
        case .loading:
            chartCard(pts, average: average).opacity(0.35).overlay { ProgressView() }
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Label("Could not load these days", systemImage: "wifi.exclamationmark").font(.headline)
                Text("Check your connection and try again.").font(.footnote).foregroundStyle(SnoopStyle.secondary)
                Button("Retry") { Task { await load() } }.buttonStyle(.bordered).font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
        case .loaded:
            if with.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No days yet", systemImage: "calendar").font(.headline)
                    Text("Days fill in as the strap syncs. Come back after the first full day.").font(.footnote).foregroundStyle(SnoopStyle.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
            } else {
                chartCard(pts, average: average)
                dailyRows(pts)
            }
        }
    }

    private func comparisonCaption(with: [Int]) -> String {
        guard days.isLoaded else { return "loading" }
        let total = with.reduce(0, +)
        let missing = scope.days - with.count
        var parts = ["\(total.formatted()) in \(scope.days) days"]
        if missing > 0 { parts.append(missing == 1 ? "1 day without data" : "\(missing) days without data") }
        return parts.joined(separator: " · ")
    }

    private func chartCard(_ pts: [DayPoint], average: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Daily steps").font(.subheadline.weight(.medium))
            Chart {
                ForEach(pts) { p in
                    BarMark(x: .value("Day", p.date, unit: .day), y: .value("Steps", p.steps ?? 0))
                        .foregroundStyle(Calendar.current.isDateInToday(p.date) ? SnoopStyle.steps : SnoopStyle.steps.opacity(0.65))
                        .cornerRadius(3)
                }
                if average > 0 {
                    RuleMark(y: .value("avg", average))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(dash: [3, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Average").font(.caption2).foregroundStyle(SnoopStyle.secondary)
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: scope == .week ? 1 : 7)) { _ in
                    AxisValueLabel(format: scope == .week ? .dateTime.weekday(.narrow) : .dateTime.day().month(.abbreviated))
                        .font(.caption2)
                }
            }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .frame(height: chartHeight)
            .accessibilityLabel(scope == .week ? "Walking steps for the last 7 days" : "Walking steps for the last 30 days")
            .accessibilityValue("average \(Int(average.rounded()).formatted()) a day")
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture().onEnded { value in
                                guard let plot = proxy.plotFrame else { return }
                                let x = value.location.x - geo[plot].origin.x
                                if let date = proxy.value(atX: x, as: Date.self) {
                                    open(Calendar.current.startOfDay(for: date))
                                }
                            }
                        )
                }
            }
        }
    }

    /// A visible, accessible alternative to selecting a bar in the chart.
    private func dailyRows(_ points: [DayPoint]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("By day").font(.headline).padding(.bottom, 12).accessibilityAddTraits(.isHeader)
            ForEach(points.reversed()) { point in
                Button { open(point.date) } label: {
                    HStack {
                        Text(ActivityView.dayTitle(point.date)).font(.subheadline)
                        Spacer()
                        Text(point.steps.map { $0.formatted() } ?? "—").font(.subheadline.weight(.medium)).monospacedDigit()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(SnoopStyle.secondary)
                    }
                    .padding(.vertical, 15)
                    .overlay(alignment: .top) { Rectangle().fill(SnoopStyle.separator).frame(height: 0.5) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(ActivityView.dayTitle(point.date)), \(point.steps.map { "\($0) steps" } ?? "no data")")
                .accessibilityHint("Opens this day")
            }
        }
    }

    /// The day pushed from the comparison; nil once the user comes back.
    @State private var selectedDay: Date?

    private func open(_ day: Date) {
        guard day <= today, days.isLoaded else { return }
        selectedDay = day
    }

    // MARK: - Data

    private func summary(for day: Date) -> SnoopAPI.Day? {
        days.rows.first { Self.day($0.day) == day }
    }

    private func load() async {
        guard !model.strap.serial.isEmpty, Settings.isConfigured else {
            days = .failed("Set up the server connection under Profile → Advanced.")
            return
        }
        if case .failed = days { days = .loading }
        async let w: Void = model.activity.reload(device: model.strap.serial)
        do {
            days = .loaded(try await SnoopAPI.days(deviceId: model.strap.serial, limit: 31))
        } catch {
            days = .failed(error.localizedDescription)
        }
        _ = try? await w
    }

    static func day(_ text: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: text)
    }
}
