import SwiftUI

struct SleepEditorView: View {
    private static let maximumDuration: TimeInterval = 24 * 60 * 60
    let mode: SleepEditorMode
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var chosenKind: String?
    @State private var neighbours: [SnoopAPI.SleepSession] = []
    @State private var mergeId: Int64?
    @State private var minutes: [SnoopAPI.Minute] = []
    @State private var selection: Date?
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?
    @State private var chartError: String?
    @State private var request: WorkoutCorrection?
    init(mode: SleepEditorMode) {
        self.mode = mode
        _end = State(initialValue: mode.record.endTs)
        _start = State(initialValue: mode.record.startTs)
        _chosenKind = State(initialValue: mode.action == "merge" ? nil : mode.record.kind)
    }
    private var neighbour: SnoopAPI.SleepSession? { neighbours.first { $0.id == mergeId } }
    // Joining a main sleep and a nap remains main sleep whichever card opened
    // the editor. An explicit type choice still takes precedence.
    private var kind: String {
        chosenKind ?? (mode.record.kind == "main" || neighbour?.kind == "main" ? "main" : "nap")
    }
    private var from: Date { neighbour.map { min(start, $0.startTs) } ?? start }
    private var to: Date { neighbour.map { max(end, $0.endTs) } ?? end }
    private var timezone: TimeZone { TimeZone(identifier: mode.record.timezone) ?? .current }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: Binding(get: { kind }, set: { chosenKind = $0 })) { Text("Main sleep").tag("main"); Text("Nap").tag("nap") }.accessibilityIdentifier("sleepType")
                }.listRowBackground(SnoopStyle.surface)
                if mode.action == "merge" {
                    Section("Merge with") {
                        if loading { ProgressView("Loading sleep") }
                        else if neighbours.isEmpty { Text("No nearby sleep recordings").foregroundStyle(SnoopStyle.secondary) }
                        ForEach(neighbours) { row in
                            Button { mergeId = row.id } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(row.name)
                                        Text(row.startTs.formatted(date: .abbreviated, time: .shortened) + " – " + row.endTs.formatted(date: .omitted, time: .shortened))
                                            .font(.caption).foregroundStyle(SnoopStyle.secondary)
                                    }
                                    Spacer()
                                    if row.id == mergeId { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                                }.frame(minHeight: 44)
                            }.foregroundStyle(SnoopStyle.text)
                        }
                    }.listRowBackground(SnoopStyle.surface)
                    if neighbour != nil {
                        Section {
                            LabeledContent("Sleep period", value: "\(Int(to.timeIntervalSince(from) / 60)) min")
                            Text("Awake time and missing readings stay separate.").font(.footnote).foregroundStyle(SnoopStyle.secondary)
                        }.listRowBackground(SnoopStyle.surface)
                    }
                } else {
                    Section {
                        DatePicker("Fell asleep", selection: $start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        DatePicker("Woke up", selection: $end, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    }.listRowBackground(SnoopStyle.surface)
                }
                Section {
                    WorkoutWindowChart(minutes: minutes, start: from, end: max(to, from.addingTimeInterval(1)), split: nil, selected: $selection)
                    if let chartError { Text(chartError).font(.footnote).foregroundStyle(SnoopStyle.secondary) }
                }.listRowBackground(SnoopStyle.surface)
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityLabel("Unable to save. \(error)") }.listRowBackground(SnoopStyle.surface) }
            }
            .scrollContentBackground(.hidden).snoopScreen()
            .navigationTitle(mode.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { HStack { if saving { ProgressView() }; Text("Save") } }
                        .disabled(saving).accessibilityIdentifier("saveSleep")
                }
            }
            .interactiveDismissDisabled(saving)
            .task { await loadNeighbours() }
            .task(id: "\(from)-\(to)") { await loadReadings() }
        }
        .environment(\.timeZone, timezone)
        .tint(SnoopStyle.load).foregroundStyle(SnoopStyle.text).presentationBackground(SnoopStyle.background)
    }
    private func loadNeighbours() async {
        guard mode.action == "merge" else { return }
        let row = mode.record
        loading = true; defer { loading = false }
        do {
            let rows = try await SnoopAPI.sleepSessions(deviceId: model.strap.serial, from: start.addingTimeInterval(-Self.maximumDuration), to: end.addingTimeInterval(Self.maximumDuration)).filter { $0.id != row.id }
            neighbours = [rows.filter { $0.endTs <= start }.max { $0.endTs < $1.endTs }, rows.filter { $0.startTs >= end }.min { $0.startTs < $1.startTs }].compactMap { $0 }.sorted { gap($0) < gap($1) }
        } catch { self.error = error.localizedDescription }
    }
    private func gap(_ row: SnoopAPI.SleepSession) -> TimeInterval {
        max(row.startTs.timeIntervalSince(end), start.timeIntervalSince(row.endTs), 0)
    }
    private func loadReadings() async {
        guard to > from, to.timeIntervalSince(from) <= Self.maximumDuration else { minutes = []; return }
        do {
            let rows = try await SnoopAPI.minutes(deviceId: model.strap.serial, window: from...to)
            guard !Task.isCancelled else { return }; minutes = rows; chartError = nil
        } catch { if !Task.isCancelled { minutes = []; chartError = "Couldn’t load the chart. You can still save your times." } }
    }
    private func save() async {
        guard !model.strap.serial.isEmpty else { error = "Connect your WHOOP to save this change."; return }
        guard to > from, to.timeIntervalSince(from) <= Self.maximumDuration else { error = "Choose a wake-up time after falling asleep, within 24 hours."; return }
        var targets = [WorkoutCorrection.Target(mode.record)]
        if mode.action == "merge" { guard let neighbour else { error = "Choose a sleep recording to merge."; return }; targets.append(.init(neighbour)) }
        let draft = WorkoutCorrection(action: mode.action, targets: targets, intervals: [.init(startTs: from, endTs: to, kind: kind)])
        if request?.hasSameChange(as: draft) != true { request = draft }
        guard let request else { return }
        saving = true; defer { saving = false }
        do { try await model.sleep.save(device: model.strap.serial, command: request); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
