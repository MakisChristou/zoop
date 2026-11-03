import SwiftUI
import SnoopECG

struct ECGRecordingView: View {
    let recording: ECGRecording
    var done: (() -> Void)?
    @State private var samples: [Int32] = []
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Recording saved", systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(SnoopStyle.favourable)
                Text("Your ECG.").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text(recording.startedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(SnoopStyle.secondary)
            }
            ECGWaveform(samples: samples)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 32) { metrics }
                VStack(alignment: .leading, spacing: 20) { metrics }
            }
            Label("This recording does not include a rhythm assessment.", systemImage: "info.circle")
                .font(.footnote).foregroundStyle(SnoopStyle.secondary)
            if let done { Button("Done", action: done).buttonStyle(ECGActionStyle()) }
            if let exportURL {
                ShareLink(item: exportURL) { Label("Share recording", systemImage: "square.and.arrow.up") }
                    .buttonStyle(ECGActionStyle(primary: false))
            }
            if let exportError { Text(exportError).font(.footnote).foregroundStyle(SnoopStyle.secondary) }
        }
        .task(id: recording.id) {
            let value = recording
            let result = await Task.detached(priority: .userInitiated) { () -> ([Int32], URL?, String?) in
                let values = value.filteredSamples
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("ECG-\(value.id.uuidString).csv")
                let header = "# Snoop ECG recording\n# Recorded: \(value.startedAt.ISO8601Format())\n# Uncalibrated native counts. Sample rate unknown. No rhythm assessment.\nsample_index,native_count\n"
                let csv = header + values.enumerated().map { "\($0.offset),\($0.element)" }.joined(separator: "\n")
                do { try csv.write(to: url, atomically: true, encoding: .utf8); return (values, url, nil) }
                catch { return (values, nil, "Couldn’t prepare the recording for sharing.") }
            }.value
            guard !Task.isCancelled else { return }
            samples = result.0; exportURL = result.1; exportError = result.2
        }
    }
    private var metrics: some View {
        Group {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(recording.duration.rounded())) sec").font(.title.weight(.semibold)).monospacedDigit()
                Text("Capture window").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(samples.count.formatted()).font(.title.weight(.semibold)).monospacedDigit()
                Text("ECG samples").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            }
        }
    }
}
