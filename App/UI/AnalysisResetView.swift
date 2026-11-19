import SwiftUI

/// A preview is tied to the server revisions it describes; changed history must be reviewed again.
struct AnalysisResetView: View {
    var targetId: Int64? = nil
    var isSheet = false
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var domain: String
    @State private var allHistory = false
    @State private var firstDay = Calendar.current.startOfDay(for: Date())
    @State private var lastDay = Calendar.current.startOfDay(for: Date())
    @State private var preview: ZoopAPI.ResetPreview?
    @State private var command: ZoopAPI.ResetCommand?
    @State private var undoCommand: ZoopAPI.ResetUndo?
    @State private var history: [ZoopAPI.ResetHistory] = []
    @State private var saving = false
    @State private var error: String?
    @State private var message: String?
    init(domain: String = "both", targetId: Int64? = nil, isSheet: Bool = false) {
        self.targetId = targetId; self.isSheet = isSheet; _domain = State(initialValue: domain)
    }
    private var domains: [String] { domain == "both" ? ["sleep", "workout"] : [domain] }
    private var scope: ZoopAPI.ResetScope {
        let from = Calendar.current.startOfDay(for: firstDay)
        let to = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: lastDay)) ?? lastDay
        return .init(domains: domains, from: allHistory || targetId != nil ? nil : from, to: allHistory || targetId != nil ? nil : to, targetId: targetId)
    }
    var body: some View {
        Form {
            if targetId == nil {
                Section {
                    Picker("Reset", selection: $domain) { Text("Sleep and workouts").tag("both"); Text("Sleep").tag("sleep"); Text("Workouts").tag("workout") }
                    Toggle("All recorded history", isOn: $allHistory)
                    if !allHistory {
                        DatePicker("From", selection: $firstDay, in: ...Date(), displayedComponents: .date)
                        DatePicker("Through", selection: $lastDay, in: ...Date(), displayedComponents: .date)
                    }
                }.listRowBackground(ZoopStyle.surface).disabled(saving)
            }
            Section {
                Text("Rebuild from recordings and clear your manual changes in this range.").foregroundStyle(ZoopStyle.secondary)
                if preview == nil {
                    Button { Task { await review() } } label: { HStack { Text("Review reset"); Spacer(); if saving { ProgressView() } } }
                        .disabled(saving).frame(minHeight: 44)
                }
            } footer: { Text("Your recordings are kept. You can undo the reset.") }
                .listRowBackground(ZoopStyle.surface)
            if let preview {
                Section("Review reset") {
                    LabeledContent("From", value: preview.from.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("To", value: preview.to.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Manual changes", value: String(preview.manualChanges))
                    if preview.expanded { Text("Includes linked edits outside your selection.").font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary) }
                    Button(role: .destructive) { Task { await reset() } } label: {
                        HStack { Text(command == nil ? "Reset to automatic" : "Retry reset"); Spacer(); if saving { ProgressView() } }
                    }.foregroundStyle(ZoopStyle.heartRate).disabled(saving).frame(minHeight: 44).accessibilityIdentifier("confirmAnalysisReset")
                    Button("Cancel") { self.preview = nil; command = nil; error = nil }.disabled(saving)
                }.listRowBackground(ZoopStyle.surface)
            }
            if let message {
                Section {
                    Label(message, systemImage: model.analysisUpdating ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                        .font(ZoopType.subheadline)
                }.listRowBackground(ZoopStyle.surface)
            }
            if let error { Section { Text(error).foregroundStyle(.red) }.listRowBackground(ZoopStyle.surface) }
            if !history.isEmpty {
                Section("Recent resets") {
                    ForEach(history) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row.domains.count == 2 ? "Sleep and workouts" : row.domains.first == "sleep" ? "Sleep" : "Workouts").font(ZoopType.font(size: 14, weight: .medium, relativeTo: .subheadline))
                            Text(row.from.formatted(date: .abbreviated, time: .omitted) + " – " + row.to.formatted(date: .abbreviated, time: .omitted)).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                            Button("Undo reset") { Task { await undo(row) } }.disabled(saving).frame(minHeight: 44)
                        }
                    }
                }.listRowBackground(ZoopStyle.surface)
            }
        }
        .scrollContentBackground(.hidden).zoopScreen().foregroundStyle(ZoopStyle.text).tint(ZoopStyle.load)
        .navigationTitle("Reset to automatic").navigationBarTitleDisplayMode(.inline)
        .toolbar { if isSheet { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(saving) } } }
        .interactiveDismissDisabled(saving)
        .onChange(of: scope) { _, _ in preview = nil; command = nil; error = nil }
        .onChange(of: model.analysisUpdating) { _, updating in if !updating && message != nil { message = "History updated" } }
        .task { await loadHistory() }
    }
    private func review() async {
        guard !model.strap.serial.isEmpty else { error = "Sync your WHOOP first."; return }
        guard allHistory || targetId != nil || lastDay >= firstDay else { error = "Choose an end date on or after the start."; return }
        saving = true; defer { saving = false }
        do { preview = try await ZoopAPI.resetPreview(deviceId: model.strap.serial, scope: scope); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func reset() async {
        guard let preview else { return }
        if command == nil { command = .init(scope: scope, token: preview.token) }
        guard let command else { return }
        saving = true; defer { saving = false }
        do {
            _ = try await ZoopAPI.resetAnalysis(deviceId: model.strap.serial, command: command)
            self.preview = nil; self.command = nil; error = nil; message = "Updating history"
            model.refreshAnalysis(); await loadHistory()
        } catch {
            self.error = error.localizedDescription
            if case ZoopAPI.Failure.server(409, _) = error { self.preview = nil; self.command = nil }
        }
    }
    private func undo(_ row: ZoopAPI.ResetHistory) async {
        if undoCommand?.resetId != row.operationId { undoCommand = .init(resetId: row.operationId) }
        guard let undoCommand else { return }
        saving = true; defer { saving = false }
        do {
            _ = try await ZoopAPI.undoReset(deviceId: model.strap.serial, command: undoCommand)
            self.undoCommand = nil; error = nil; message = "Reset undone · updating history"
            model.refreshAnalysis(); await loadHistory()
        } catch { self.error = error.localizedDescription }
    }
    private func loadHistory() async {
        guard !model.strap.serial.isEmpty else { return }
        do { history = try await ZoopAPI.resetHistory(deviceId: model.strap.serial) }
        catch { self.error = error.localizedDescription }
    }
}
