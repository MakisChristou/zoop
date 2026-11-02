import SwiftUI

struct WorkoutEditorView: View {
    let mode: WorkoutEditorMode
    let onSaved: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var split: Date
    @State private var kind: ActivityKind
    @State private var secondKind: ActivityKind
    @State private var neighbours: [SnoopAPI.Workout] = []
    @State private var mergeId: Int64?
    @State private var minutes: [SnoopAPI.Minute] = []
    @State private var chartSelection: Date?
    @State private var saving = false
    @State private var loading = false
    @State private var error: String?
    @State private var chartError: String?
    @State private var lastRequest: WorkoutCorrection?
    private static let maximumDuration: TimeInterval = 24 * 60 * 60

    init(mode: WorkoutEditorMode, onSaved: @escaping () -> Void) {
        self.mode = mode; self.onSaved = onSaved
        let end = mode.workout.endTs
        let start = mode.workout.startTs
        _start = State(initialValue: start); _end = State(initialValue: end)
        _split = State(initialValue: Date(timeIntervalSince1970: floor(start.addingTimeInterval(end.timeIntervalSince(start) / 2).timeIntervalSince1970 / 60) * 60))
        let kind = ActivityKind.named(mode.workout.kind)
        _kind = State(initialValue: kind); _secondKind = State(initialValue: kind)
    }

    private var merged: SnoopAPI.Workout? { neighbours.first { $0.id == mergeId } }
    private var previewStart: Date { merged.map { min(start, $0.startTs) } ?? start }
    private var previewEnd: Date { merged.map { max(end, $0.endTs) } ?? end }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(mode.action == "split" ? "First workout" : "Type", selection: $kind) {
                        ForEach(ActivityKind.allCases) { Text($0.name).tag($0) }
                    }
                    if mode.action == "split" {
                        Picker("Second workout", selection: $secondKind) {
                            ForEach(ActivityKind.allCases) { Text($0.name).tag($0) }
                        }
                    }
                }
                .listRowBackground(SnoopStyle.surface)
                if mode.action == "merge" {
                    Section("Merge with") {
                        if loading { ProgressView("Loading workouts") }
                        else if neighbours.isEmpty { Text("No neighbouring workouts").foregroundStyle(SnoopStyle.secondary) }
                        ForEach(neighbours) { workout in
                            Button {
                                mergeId = workout.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(ActivityKind.named(workout.kind).name)
                                        Text(workout.startTs.formatted(date: .abbreviated, time: .shortened) + " – " + workout.endTs.formatted(date: .omitted, time: .shortened))
                                            .font(.caption).foregroundStyle(SnoopStyle.secondary)
                                    }
                                    Spacer()
                                    if mergeId == workout.id { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                                }.frame(minHeight: 44)
                            }.foregroundStyle(SnoopStyle.text)
                        }
                    }
                    .listRowBackground(SnoopStyle.surface)
                    if merged != nil {
                        Section {
                            LabeledContent("Duration", value: "\(Int(previewEnd.timeIntervalSince(previewStart) / 60)) min")
                            Text("Includes the rest between workouts").font(.footnote).foregroundStyle(SnoopStyle.secondary)
                        }
                        .listRowBackground(SnoopStyle.surface)
                    }
                } else if mode.action == "split" {
                    Section {
                        DatePicker("Split at", selection: $split, in: start...end, displayedComponents: [.date, .hourAndMinute])
                        LabeledContent("First workout", value: "\(max(0, Int(split.timeIntervalSince(start) / 60))) min")
                        LabeledContent("Second workout", value: "\(max(0, Int(end.timeIntervalSince(split) / 60))) min")
                    }
                    .listRowBackground(SnoopStyle.surface)
                } else {
                    Section {
                        DatePicker("Start", selection: $start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        DatePicker("End", selection: $end, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    }
                    .listRowBackground(SnoopStyle.surface)
                }
                Section {
                    if loading && minutes.isEmpty { ProgressView("Loading readings") }
                    else { WorkoutWindowChart(minutes: minutes, start: previewStart, end: max(previewEnd, previewStart.addingTimeInterval(1)), split: mode.action == "split" ? split : nil, selected: $chartSelection) }
                    if let chartError { Text(chartError).font(.footnote).foregroundStyle(SnoopStyle.secondary) }
                }
                .listRowBackground(SnoopStyle.surface)
                if let error {
                    Section { Text(error).foregroundStyle(.red).accessibilityLabel("Unable to save. \(error)") }
                    .listRowBackground(SnoopStyle.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .snoopScreen()
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        HStack { if saving { ProgressView() }; Text("Save") }
                    }.disabled(saving).accessibilityIdentifier("saveWorkout")
                }
            }
            .interactiveDismissDisabled(saving)
            .task { await loadNeighbours() }
            .task(id: "\(previewStart.timeIntervalSince1970)-\(previewEnd.timeIntervalSince1970)") { await loadMinutes() }
            .onChange(of: chartSelection) { _, value in
                guard mode.action == "split", let value else { return }
                let minute = Date(timeIntervalSince1970: (value.timeIntervalSince1970 / 60).rounded() * 60)
                if minute > start && minute < end { split = minute }
            }
        }.tint(SnoopStyle.load).foregroundStyle(SnoopStyle.text)
        .presentationBackground(SnoopStyle.background)
    }

    private func loadNeighbours() async {
        guard mode.action == "merge" else { return }
        let workout = mode.workout
        loading = true
        defer { loading = false }
        do {
            let rows = try await SnoopAPI.workouts(deviceId: model.strap.serial, limit: 500, from: start.addingTimeInterval(-Self.maximumDuration), to: end.addingTimeInterval(Self.maximumDuration))
                .filter { $0.id != workout.id }
            neighbours = [rows.filter { $0.endTs <= start }.max { $0.endTs < $1.endTs }, rows.filter { $0.startTs >= end }.min { $0.startTs < $1.startTs }].compactMap { $0 }
        } catch { self.error = "Couldn’t load nearby workouts. Check your connection and reopen the editor." }
    }

    private func loadMinutes() async {
        guard previewEnd > previewStart, previewEnd.timeIntervalSince(previewStart) <= Self.maximumDuration else { minutes = []; return }
        do {
            let loaded = try await SnoopAPI.minutes(deviceId: model.strap.serial, window: previewStart...previewEnd)
            guard !Task.isCancelled else { return }
            minutes = loaded; chartError = nil
        } catch {
            guard !Task.isCancelled else { return }
            minutes = []; chartError = "Couldn’t load the heart-rate chart. Your times can still be saved."
        }
    }

    private func save() async {
        guard !model.strap.serial.isEmpty else { error = "Connect your WHOOP to save this change."; return }
        guard previewEnd > previewStart, previewEnd.timeIntervalSince(previewStart) <= Self.maximumDuration else {
            error = "Choose an end after the start, within 24 hours."; return
        }
        var targets = [WorkoutCorrection.Target(mode.workout)]
        var intervals = [WorkoutCorrection.Interval(startTs: previewStart, endTs: previewEnd, kind: kind.rawValue)]
        if mode.action == "merge" {
            guard let merged else { error = "Choose a workout to merge with."; return }
            targets.append(WorkoutCorrection.Target(merged))
        }
        if mode.action == "split" {
            guard split > start, split < end else { error = "Choose a split time inside the workout."; return }
            intervals = [.init(startTs: start, endTs: split, kind: kind.rawValue), .init(startTs: split, endTs: end, kind: secondKind.rawValue)]
        }
        let action: String
        if mode.action == "edit", start == mode.workout.startTs, end == mode.workout.endTs {
            action = "label"
        } else { action = mode.action }
        var request = WorkoutCorrection(action: action, targets: targets, intervals: intervals)
        if let lastRequest, request.hasSameChange(as: lastRequest) { request = lastRequest }
        lastRequest = request
        saving = true
        defer { saving = false }
        do {
            try await model.activity.save(device: model.strap.serial, command: request)
            onSaved(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
