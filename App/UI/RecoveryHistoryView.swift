import ZoopData
import SwiftUI

/// Shared by Trends and the detail opened from Today's Recovery ring.
struct RecoveryHistoryView: View {
    var initialDay: Date?
    var refreshID = 0
    var detail = false
    var insights: MorningInsights?
    var onSelection: (Date, String) -> Void = { _, _ in }
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var history = RecoveryHistoryStore()
    private var snapshot: RecoveryHistoryStore.Snapshot? {
        history.value(device: model.strap.serial, connection: Settings.connectionID)
    }

    var body: some View {
        VStack(spacing: 12) {
            if let snapshot {
                RecoveryHistoryChart(snapshot: snapshot, initialDay: initialDay.map { DayKey.string($0) } ?? DayKey.string(snapshot.now, timeZone: snapshot.calendar.timeZone), detail: detail, insights: insights, onSelection: onSelection)
            } else if model.strap.serial.isEmpty {
                Text("No recovery history").font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
            } else if !history.failed {
                ProgressView().frame(maxWidth: .infinity).frame(height: 280)
                    .accessibilityLabel("Loading recovery history")
            }
            if history.failed {
                Button("Couldn’t update recovery. Retry") { Task { await load() } }
                    .font(ZoopType.subheadline).frame(minHeight: 44)
                    .accessibilityIdentifier("retryRecoveryHistory")
            }
        }
        .zoopLoading(history.loading && snapshot != nil, label: "Updating recovery history")
        .task(id: "\(model.strap.serial)-\(Settings.connectionID.hashValue)-\(model.analysisRevision)-\(model.sleep.changeToken)-\(refreshID)-\(scenePhase)") {
            guard scenePhase == .active else { return }
            repeat {
                await load()
                guard snapshot?.rows.contains(where: { $0.recovery.isPending }) == true, !history.failed else { return }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            } while !Task.isCancelled
        }
    }

    private func load() async {
        let device = model.strap.serial, connection = Settings.connectionID
        await history.reload(device: device, connection: connection) {
            model.strap.serial == device && Settings.connectionID == connection
        }
    }
}
