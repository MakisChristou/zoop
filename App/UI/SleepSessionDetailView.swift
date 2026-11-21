import SwiftUI

struct SleepSessionDetailView: View {
    let initial: ZoopAPI.SleepSession
    @Environment(AppModel.self) private var model
    @State private var snapshot: ZoopAPI.SleepSession?
    @State private var editor: SleepEditorMode?
    @State private var reset = false
    @State private var remove = false
    @State private var saving = false
    @State private var error: String?
    @State private var removalRequest: WorkoutCorrection?
    private var row: ZoopAPI.SleepSession { model.sleep.items.first { $0.id == initial.id } ?? snapshot ?? initial }
    var body: some View {
        Group {
            if row.isActive, let night = row.night {
                SleepDetailView(night: night, sessionID: row.id, timezone: TimeZone(identifier: row.timezone) ?? .current)
            } else {
                ContentUnavailableView {
                    Label(row.status == "removed" ? "Sleep removed" : row.status == "superseded" ? "Sleep replaced" : "Updating sleep", systemImage: "moon.zzz")
                } actions: {
                    if row.status == "removed", let edit = row.lastEdit { Button("Restore sleep") { Task { await undo(edit) } }.disabled(saving) }
                }
            }
        }
        .zoopLoading(saving, label: "Saving sleep")
        .zoopScreen().navigationTitle(row.name).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if row.isActive {
                        Button("Edit sleep", systemImage: "pencil") { editor = .edit(row) }
                        Button("Merge sleep", systemImage: "arrow.triangle.merge") { editor = .merge(row) }
                        if let edit = row.lastEdit { Button("Undo last change", systemImage: "arrow.uturn.backward") { Task { await undo(edit) } } }
                    }
                    Button("Reset to automatic", systemImage: "arrow.counterclockwise") { reset = true }
                    if row.isActive { Button("Remove sleep", systemImage: "trash", role: .destructive) { remove = true } }
                } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Sleep options").disabled(saving)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let error { Text(error).font(ZoopType.footnote).foregroundStyle(.red).padding().frame(maxWidth: .infinity).background(ZoopStyle.surface) }
                SleepNotice()
            }
        }
        .sheet(item: $editor, onDismiss: { Task { await refresh() } }) { SleepEditorView(mode: $0) }
        .sheet(isPresented: $reset, onDismiss: { Task { await refresh() } }) { NavigationStack { AnalysisResetView(domain: "sleep", targetId: row.id, isSheet: true) }.presentationBackground(ZoopStyle.background) }
        .confirmationDialog("Remove this sleep recording?", isPresented: $remove, titleVisibility: .visible) {
            Button("Remove sleep", role: .destructive) { Task { await removeSleep() } }
        } message: { Text("Your recorded data is kept. You can restore this sleep later.") }
        .task(id: model.sleep.changeToken) { await refresh() }
        .onChange(of: model.analysisRevision) { _, _ in Task { await refresh() } }
    }
    private func refresh() async {
        do { snapshot = try await ZoopAPI.sleepSession(deviceId: model.dataDevice, id: initial.id) }
        catch { self.error = error.localizedDescription }
    }
    private func undo(_ edit: String) async {
        saving = true; defer { saving = false }
        do { try await model.sleep.undo(device: model.dataDevice, id: edit); error = nil; await refresh() }
        catch { self.error = error.localizedDescription }
    }
    private func removeSleep() async {
        let draft = WorkoutCorrection(action: "remove", targets: [.init(row)])
        if removalRequest?.hasSameChange(as: draft) != true { removalRequest = draft }
        guard let removalRequest else { return }
        saving = true; defer { saving = false }
        do { try await model.sleep.save(device: model.dataDevice, command: removalRequest); error = nil; await refresh() }
        catch { self.error = error.localizedDescription }
    }
}
