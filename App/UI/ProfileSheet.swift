import SwiftUI
import UserNotifications

/// A compact settings hub; the body form is a separate destination inside the sheet.
struct ProfileSheet: View {
    enum Page: Hashable {
        case body, device, advanced, server, diagnostics, health, ecg
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Page] = []
    private let open: Page?

    init(open: Page? = nil) {
        self.open = open
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle").font(.largeTitle).foregroundStyle(SnoopStyle.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Personal profile").font(.headline)
                            Text("Body measurements").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                Section {
                    NavigationLink(value: Page.body) { Label("Edit profile", systemImage: "person") }
                    NavigationLink(value: Page.health) { Label("Apple Health", systemImage: "heart") }
                    NavigationLink(value: Page.ecg) { Label("ECG", systemImage: "waveform.path.ecg") }
                        .accessibilityIdentifier("openECG")
                    NavigationLink(value: Page.device) {
                        HStack {
                            Label("My WHOOP", systemImage: "sensor.tag.radiowaves.forward")
                            Spacer()
                            Text(statusText).font(.caption).foregroundStyle(SnoopStyle.secondary)
                        }
                    }
                    .accessibilityLabel("Device, \(statusText)")
                    notificationRow
                }
                .listRowBackground(SnoopStyle.surface)
                Section {
                    NavigationLink(value: Page.advanced) { Label("Advanced", systemImage: "slider.horizontal.3") }
                }
                .listRowBackground(SnoopStyle.surface)
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
            .listSectionSpacing(.compact)
            .snoopScreen()
            .navigationTitle("Profile & settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.medium))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .body: BodyProfileView()
                case .health: AppleHealthView()
                case .ecg: ECGView()
                case .device: DeviceView()
                case .advanced: AdvancedSettingsView()
                case .server: ServerSettingsView()
                case .diagnostics: DiagnosticsView()
                }
            }
            .task { await model.battery.refreshAuthorization() }
            .onAppear { if let open, path.isEmpty { path = [open] } }
        }
        .tint(SnoopStyle.text)
        .presentationDragIndicator(.visible)
        .presentationBackground(SnoopStyle.background)
    }

    private var notificationRow: some View {
        Button {
            Task {
                if model.battery.authorization == .notDetermined {
                    await model.battery.requestNotificationsIfNeeded()
                } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    await UIApplication.shared.open(url)
                }
            }
        } label: {
            HStack {
                Label("Notifications", systemImage: "bell")
                Spacer()
                Text(authorizationText).foregroundStyle(SnoopStyle.secondary)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Notifications, \(authorizationText)")
        .accessibilityHint(model.battery.authorization == .notDetermined ? "Asks for permission" : "Opens iOS Settings")
    }

    private var authorizationText: String {
        switch model.battery.authorization {
        case .authorized, .provisional, .ephemeral: "On"
        case .denied: "Off"
        case .notDetermined: "Set up"
        @unknown default: "Unknown"
        }
    }

    private var statusText: String {
        switch model.strap.state {
        case .ready: "Connected"
        case .connected: "Connecting…"
        case .connecting: "Connecting"
        case .scanning: "Connecting…"
        case .bluetoothOff: "Bluetooth off"
        case .failed: "Disconnected"
        }
    }
}
