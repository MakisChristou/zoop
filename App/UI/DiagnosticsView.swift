import SwiftUI

/// Upload pipeline state: what is queued on the phone, what the server accepted, and
/// the last error. Pushed from the profile sheet's Advanced group.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section("Uploads") {
                HStack {
                    Circle().fill(uploadColor).frame(width: 10, height: 10)
                    Text(uploadText)
                    Spacer()
                    if model.isUploading { ProgressView() }
                }
                .accessibilityElement(children: .combine)
                LabeledContent("Waiting to upload", value: "\((model.queued - model.heldFrames).formatted()) frames")
                if model.heldFrames > 0 {
                    LabeledContent("Saved for review", value: "\(model.heldFrames.formatted()) frames")
                    Button("Retry saved frames") { Task { await model.retryHeldFrames() } }
                }
                LabeledContent("Accepted by server", value: model.uploadStats.accepted.formatted())
                if model.uploadStats.duplicates > 0 || model.uploadStats.rejected > 0 {
                    LabeledContent("Duplicates / rejected", value: "\(model.uploadStats.duplicates) / \(model.uploadStats.rejected)")
                }
                if let error = model.uploadStats.lastError ?? model.queueError {
                    Text(error).font(ZoopType.footnote).foregroundStyle(.red)
                } else if let blocker = model.uploadBlocker {
                    Text(blocker).font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary)
                }
                Button {
                    Task { await model.flush() }
                } label: {
                    Label(model.isUploading ? "Uploading…" : "Upload now", systemImage: "icloud.and.arrow.up")
                }
                .disabled(model.uploadBlocker != nil || model.isUploading)
            }
            if let status = model.processing {
                Section("History") {
                    LabeledContent("Status", value: status.paused ? "Paused" : !status.workersHealthy || status.failedAnalysis > 0 || status.decodeFailures > 0 ? "Needs attention" : status.pendingDecode + status.pendingAnalysis > 0 ? "Catching up" : "Up to date")
                    LabeledContent("Frames to process", value: status.pendingDecode.formatted())
                    LabeledContent("Periods to analyze", value: status.pendingAnalysis.formatted())
                    if status.decodeFailures + status.failedAnalysis > 0 {
                        LabeledContent("Needs review", value: (status.decodeFailures + status.failedAnalysis).formatted())
                    }
                    if let day = status.oldestPendingDay { LabeledContent("Oldest pending", value: day) }
                }
            }
            Section {
                LabeledContent("Server", value: Settings.serverURL?.host() ?? "not set")
                LabeledContent("Sessions checked", value: model.workouts.lastCheckedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "never")
                if let error = model.processingError { Text(error).font(ZoopType.footnote).foregroundStyle(.red) }
                if let error = model.workouts.notificationError ?? model.battery.notificationError {
                    Text(error).font(ZoopType.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Server")
            } footer: {
                Text("Frames are queued on this phone and removed only after the server accepts them.")
            }
        }
        .scrollContentBackground(.hidden)
        .zoopScreen()
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var uploadColor: Color {
        if model.uploadStats.lastError != nil { return .red }
        if model.uploadStats.lastSuccess != nil { return .green }
        return .gray
    }

    private var uploadText: String {
        if model.isUploading { return "Uploading…" }
        if let error = model.uploadStats.lastError { return "Upload failed: \(error)" }
        if let at = model.uploadStats.lastSuccess {
            let age = Int(Date().timeIntervalSince(at))
            let when = age < 60 ? "\(age) s ago" : "\(age / 60) min ago"
            return "Last upload \(when): \(model.lastBatchAccepted) frames accepted"
        }
        return Settings.isConfigured ? "No upload yet" : "Not configured"
    }
}
