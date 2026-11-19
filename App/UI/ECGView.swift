import SwiftUI
import ZoopECG
import ZoopProtocol

struct ECGView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var preparing = false
    @State private var showAll = false
    @ScaledMetric(relativeTo: .caption) private var stepDiameter: CGFloat = 25
    private var recorder: ECGRecorder { model.ecg }

    var body: some View {
        @Bindable var recorder = model.ecg
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                if let cleanupError = recorder.cleanupError {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Finish stopping the previous recording", systemImage: "exclamationmark.circle").font(.headline)
                        Text(cleanupError).font(.footnote).foregroundStyle(ZoopStyle.secondary)
                        Button("Retry stopping") { recorder.recoverCleanup() }.disabled(recorder.isBusy || recorder.device == nil)
                    }.zoopCard()
                }
                switch recorder.phase {
                case .starting, .waiting, .recording, .finishing: capture
                case .saved:
                    if let recording = recorder.savedRecording {
                        ECGRecordingView(recording: recording) { preparing = false; recorder.dismissResult() }
                    }
                case .failed: failure
                case .idle:
                    if preparing { preparation }
                    else { home }
                }
            }
            .padding(ZoopStyle.gutter)
        }
        .zoopScreen()
        .navigationTitle(recorder.phase == .saved ? "ECG recording" : "ECG")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(recorder.isRecording)
        .navigationBarBackButtonHidden(recorder.isRecording || preparing)
        .toolbar {
            if preparing && !recorder.isRecording {
                ToolbarItem(placement: .topBarLeading) {
                    Button { preparing = false; recorder.dismissResult() } label: { Label("Back", systemImage: "chevron.left") }
                }
            }
        }
        .task { recorder.connectionChanged(); await recorder.reloadHistory() }
        .onChange(of: recorder.isRecording) { _, active in UIApplication.shared.isIdleTimerDisabled = active }
        .onChange(of: scenePhase) { _, phase in if phase == .background { recorder.cancel() } }
        .onDisappear { recorder.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 25) {
            VStack(alignment: .leading, spacing: 10) {
                Label(recorder.device == nil ? "WHOOP not connected" : recorder.device?.isMG == true ? "WHOOP MG connected" : "ECG needs WHOOP MG",
                      systemImage: recorder.device == nil ? "antenna.radiowaves.left.and.right.slash" : "checkmark.circle")
                    .font(.caption).foregroundStyle(ZoopStyle.secondary)
                Text("Heart rhythm").font(.title2.weight(.medium)).accessibilityAddTraits(.isHeader)
                Text("Record your heart rhythm in 30 seconds.").foregroundStyle(ZoopStyle.secondary)
            }
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 64, weight: .light)).foregroundStyle(ZoopStyle.heartRate)
                .frame(maxWidth: .infinity, minHeight: 140).zoopCard().accessibilityHidden(true)
            Button("Record ECG") { preparing = true }.buttonStyle(ECGActionStyle()).accessibilityIdentifier("recordECG")
            history
            DisclosureGroup("About this measurement") {
                Text("Use a WHOOP MG and an ECG-compatible clasp. Zoop saves the electrical signal without a rhythm assessment. Waveform timing and amplitude are not calibrated. Recording history is stored on this iPhone.")
                    .font(.footnote).foregroundStyle(ZoopStyle.secondary).padding(.top, 8)
            }.font(.subheadline).tint(ZoopStyle.secondary)
        }
    }

    private var preparation: some View {
        @Bindable var recorder = model.ecg
        return VStack(alignment: .leading, spacing: 25) {
            heading("Get comfortable.", subtitle: "Keep your WHOOP snug against your wrist.")
            ECGContactGuide()
            VStack(alignment: .leading, spacing: 18) {
                step(1, "Sit down and rest your forearm on a table.")
                step(2, "Lightly touch both clasp contacts with your other hand’s thumb and index finger.")
                step(3, "Hold still for 30 seconds.")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("WHOOP is on my").font(.subheadline).foregroundStyle(ZoopStyle.secondary)
                Picker("Wrist wearing WHOOP", selection: $recorder.wrist) {
                    Text("Left wrist").tag(ECGWrist.left)
                    Text("Right wrist").tag(ECGWrist.right)
                }.pickerStyle(.menu).tint(ZoopStyle.text).accessibilityIdentifier("ecgWrist")
            }
            if recorder.device == nil {
                Text("Connect your WHOOP MG to begin.").font(.subheadline).foregroundStyle(ZoopStyle.secondary)
                Button("Reconnect") { model.startStrap(); model.strap.connect() }.buttonStyle(ECGActionStyle(primary: false))
            } else if recorder.device?.isMG == false {
                Text("ECG requires WHOOP MG and its ECG-compatible clasp.").font(.subheadline)
            }
            Button("Begin recording") { recorder.begin() }
                .buttonStyle(ECGActionStyle()).disabled(!recorder.canStart).accessibilityIdentifier("beginECG")
        }
    }

    private var capture: some View {
        VStack(alignment: .leading, spacing: 25) {
            heading(captureTitle, subtitle: captureSubtitle)
            if recorder.phase == .recording {
                VStack(spacing: 4) {
                    Text(recorder.secondsRemaining.formatted()).font(.system(.largeTitle, design: .rounded, weight: .medium)).monospacedDigit()
                    Text("seconds remaining").font(.subheadline).foregroundStyle(ZoopStyle.secondary)
                }.frame(maxWidth: .infinity)
                ECGWaveform(samples: recorder.samples, label: "Live ECG")
                ProgressView(value: Double(30 - recorder.secondsRemaining), total: 30).tint(ZoopStyle.text)
                    .accessibilityLabel("Recording progress")
            } else { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 35) }
            if recorder.phase != .finishing {
                Button("Cancel recording") { recorder.cancel(); preparing = false }.buttonStyle(ECGActionStyle(primary: false))
            }
        }
        .accessibilityIdentifier("ecgCapture")
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: 25) {
            heading("Let’s try again.", subtitle: recorder.error ?? "The recording couldn’t be completed.")
            if recorder.savedRecording != nil {
                Button("Save recording again") { Task { await recorder.retrySave() } }.buttonStyle(ECGActionStyle())
            } else {
                ECGContactGuide()
                Button("Try again") { recorder.dismissResult(); preparing = true }.buttonStyle(ECGActionStyle()).disabled(recorder.isBusy)
            }
            Button("Not now") { recorder.dismissResult(); preparing = false }.buttonStyle(ECGActionStyle(primary: false)).disabled(recorder.isBusy)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent recordings").font(.headline).accessibilityAddTraits(.isHeader)
            if let error = recorder.historyError {
                Text(error).font(.footnote).foregroundStyle(ZoopStyle.secondary)
                Button("Reload recordings") { Task { await recorder.reloadHistory() } }
            } else if recorder.recordings.isEmpty {
                Text("No recordings yet").font(.subheadline).foregroundStyle(ZoopStyle.secondary)
            }
            ForEach(Array(recorder.recordings.prefix(showAll ? recorder.recordings.count : 3))) { item in
                NavigationLink { ECGHistoryDetail(id: item.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.path.ecg").foregroundStyle(ZoopStyle.heartRate)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.startedAt.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.weight(.semibold))
                            Text("\(item.startedAt.formatted(date: .omitted, time: .shortened)) · \(Int(item.duration.rounded())) seconds")
                                .font(.caption).foregroundStyle(ZoopStyle.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(ZoopStyle.secondary)
                    }.zoopCard()
                }.buttonStyle(PressableCardStyle())
            }
            if recorder.recordings.count > 3 { Button(showAll ? "Show recent" : "View all recordings") { showAll.toggle() }.tint(ZoopStyle.text) }
        }
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.weight(.medium)).accessibilityAddTraits(.isHeader)
            Text(subtitle).foregroundStyle(ZoopStyle.secondary)
        }
    }
    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number.formatted()).font(.caption).frame(width: stepDiameter, height: stepDiameter)
                .overlay(Circle().stroke(ZoopStyle.separator)).foregroundStyle(ZoopStyle.secondary)
            Text(text).font(.subheadline)
        }.accessibilityElement(children: .combine)
    }
    private var captureTitle: String {
        switch recorder.phase {
        case .starting: "Getting ready…"
        case .waiting: "Keep a light touch."
        case .finishing: "Finishing…"
        default: "Hold still."
        }
    }
    private var captureSubtitle: String {
        switch recorder.phase {
        case .starting: "Setting up your WHOOP."
        case .waiting: "Waiting for ECG data. Keep both contacts lightly covered."
        case .finishing: "You can relax your hand."
        default: "Keep a light touch on both contacts."
        }
    }
}
