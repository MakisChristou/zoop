import SwiftUI
import UserNotifications

/// The slide-up drawer behind the profile button: body profile, the device, notification
/// permission, and the server connection and diagnostics under Advanced. Pages push
/// inside the sheet; the close button dismisses the whole thing.
struct ProfileSheet: View {
    enum Page: Hashable {
        case device, server, diagnostics
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Page] = []
    private let open: Page?

    init(open: Page? = nil) {
        self.open = open
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                BodyProfileSection()
                Section("My device") {
                    NavigationLink(value: Page.device) {
                        HStack(spacing: 10) {
                            Circle().fill(statusColor).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(model.strap.serial.isEmpty ? "WHOOP strap" : "WHOOP \(model.strap.model)")
                                Text(statusText).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityLabel("Device, \(statusText)")
                }
                Section {
                    notificationRow
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Battery reminders and detected sessions arrive as notifications.")
                }
                Section("Advanced") {
                    NavigationLink(value: Page.server) { Label("Server connection", systemImage: "network") }
                    NavigationLink(value: Page.diagnostics) { Label("Diagnostics", systemImage: "waveform.path.ecg.rectangle") }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .device: DeviceView()
                case .server: ServerSettingsView()
                case .diagnostics: DiagnosticsView()
                }
            }
            .task { await model.battery.refreshAuthorization() }
            .onAppear { if let open, path.isEmpty { path = [open] } }
        }
        .presentationDragIndicator(.visible)
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
                Label("Notifications", systemImage: "bell.badge")
                Spacer()
                Text(authorizationText).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Notifications, \(authorizationText)")
        .accessibilityHint(model.battery.authorization == .notDetermined ? "Asks for permission" : "Opens iOS Settings")
    }

    private var authorizationText: String {
        switch model.battery.authorization {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Off"
        case .notDetermined: "Not asked yet"
        @unknown default: "Unknown"
        }
    }

    private var statusColor: Color {
        switch model.strap.state {
        case .ready: .green
        case .connected, .connecting, .scanning: .orange
        case .bluetoothOff, .failed: .red
        }
    }

    private var statusText: String {
        switch model.strap.state {
        case .ready: "Connected"
        case .connected: "Handshaking"
        case .connecting: "Connecting"
        case .scanning: "Looking for strap"
        case .bluetoothOff: "Bluetooth off"
        case .failed: "Disconnected"
        }
    }
}
