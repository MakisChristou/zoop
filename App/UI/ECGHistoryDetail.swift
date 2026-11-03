import SwiftUI
import SnoopECG

struct ECGHistoryDetail: View {
    let id: UUID
    @Environment(AppModel.self) private var model
    @State private var recording: ECGRecording?
    @State private var error: String?

    var body: some View {
        ScrollView {
            Group {
                if let recording { ECGRecordingView(recording: recording) }
                else if let error { ContentUnavailableView("Couldn’t open recording", systemImage: "exclamationmark.circle", description: Text(error)) }
                else { ProgressView("Loading recording") }
            }.padding(SnoopStyle.gutter)
        }
        .snoopScreen().navigationTitle("ECG recording").navigationBarTitleDisplayMode(.inline)
        .task(id: id) {
            do { recording = try await model.ecg.load(id: id) }
            catch { self.error = error.localizedDescription }
        }
    }
}
