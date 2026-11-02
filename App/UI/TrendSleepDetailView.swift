import SwiftUI

/// Load a full session only after opening a compact trend summary.
struct TrendSleepDetailView: View {
    let summary: SnoopAPI.Night
    @Environment(AppModel.self) private var model
    @State private var session: SnoopAPI.SleepSession?
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var loadedScope: String?
    private var scope: String { model.strap.serial + "|" + Settings.connectionID }

    var body: some View {
        Group {
            if loadedScope == scope, let session {
                SleepSessionDetailView(initial: session)
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn’t open sleep", systemImage: "moon.zzz")
                } description: { Text(error) } actions: {
                    Button("Try again") { Task { await load() } }.frame(minHeight: 44)
                }
            } else {
                ProgressView("Loading sleep").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .snoopScreen()
        .navigationTitle("Sleep details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: scope) { await load() }
    }
    private func load() async {
        let source = scope, serial = model.strap.serial, request = UUID()
        requestID = request
        session = nil; error = nil; loadedScope = nil
        do {
            let rows = try await SnoopAPI.sleepSessions(deviceId: serial, from: summary.startTs, to: summary.endTs.addingTimeInterval(1))
            guard !Task.isCancelled, scope == source, requestID == request else { return }
            guard let match = Self.match(summary, in: rows) else {
                error = "This sleep has changed. Go back and refresh Trends."; return
            }
            session = match; loadedScope = source
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, scope == source, requestID == request else { return }
            self.error = error.localizedDescription
        }
    }
    /// Exact windows win; a corrected main sleep may shift, but never substitute a nap.
    static func match(_ night: SnoopAPI.Night, in rows: [SnoopAPI.SleepSession]) -> SnoopAPI.SleepSession? {
        let main = rows.filter { $0.isActive && $0.kind == "main" }
        if let exact = main.first(where: { $0.startTs == night.startTs && $0.endTs == night.endTs }) { return exact }
        return main.filter { row in
            let overlap = min(row.endTs, night.endTs).timeIntervalSince(max(row.startTs, night.startTs))
            return overlap > 0 && overlap * 2 >= max(row.endTs.timeIntervalSince(row.startTs), night.endTs.timeIntervalSince(night.startTs))
        }.max { a, b in
            min(a.endTs, night.endTs).timeIntervalSince(max(a.startTs, night.startTs)) < min(b.endTs, night.endTs).timeIntervalSince(max(b.startTs, night.startTs))
        }
    }
}
