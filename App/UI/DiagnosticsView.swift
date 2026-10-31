import SwiftUI

/// Upload pipeline state: what is queued on the phone, what the server accepted, and
/// the last error. Pushed from the profile sheet's Advanced group.
struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel

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
                LabeledContent("Waiting to upload", value: "\(model.queued.formatted()) frames")
                LabeledContent("Accepted by server", value: model.uploadStats.accepted.formatted())
                if model.uploadStats.duplicates > 0 || model.uploadStats.rejected > 0 {
                    LabeledContent("Duplicates / rejected", value: "\(model.uploadStats.duplicates) / \(model.uploadStats.rejected)")
                }
                if let error = model.uploadStats.lastError ?? model.queueError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                } else if let blocker = model.uploadBlocker {
                    Text(blocker).font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    Task { await model.flush() }
                } label: {
                    Label(model.isUploading ? "Uploading…" : "Upload now", systemImage: "icloud.and.arrow.up")
                }
                .disabled(model.uploadBlocker != nil || model.isUploading)
            }
            Section {
                LabeledContent("Server", value: Settings.serverURL?.host() ?? "not set")
                LabeledContent("Sessions checked", value: model.workouts.lastCheckedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "never")
                if let error = model.workouts.notificationError ?? model.battery.notificationError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Server")
            } footer: {
                Text("Frames are queued on this phone and removed only after the server accepts them.")
            }
        }
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
