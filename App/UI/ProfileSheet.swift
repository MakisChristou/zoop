import SwiftUI
import UserNotifications

/// A compact settings hub; the body form is a separate destination inside the sheet.
struct ProfileSheet: View {
    enum Page: Hashable {
        case body, device, advanced, server, diagnostics, health, ecg, notifications
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Page] = []
    @State private var editingPhoto = false
    private var photoScope: ProfilePhotoStore.Scope { .init(device: model.dataDevice, connection: Settings.connectionID) }
    private let open: Page?

    init(open: Page? = nil) {
        self.open = open
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack(spacing: 12) {
                        Button { editingPhoto = true } label: { ProfileAvatar(size: 64) }
                            .buttonStyle(.plain).accessibilityLabel("Edit profile photo")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Personal profile").font(ZoopType.headline)
                            Button(model.photo.image(for: photoScope) == nil ? "Add photo" : "Change photo") { editingPhoto = true }
                                .font(ZoopType.subheadline).frame(minHeight: 44).accessibilityIdentifier("editProfilePhoto")
                        }
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                Section {
                    NavigationLink(value: Page.body) { Label("Edit profile", systemImage: "person") }
                    NavigationLink(value: Page.health) { Label("Apple Health", systemImage: "heart") }
                    if BuildFeatures.manualECG {
                        NavigationLink(value: Page.ecg) { Label("ECG", systemImage: "waveform.path.ecg") }
                            .accessibilityIdentifier("openECG")
                    }
                    NavigationLink(value: Page.device) {
                        HStack {
                            Label("My WHOOP", systemImage: "sensor.tag.radiowaves.forward")
                            Spacer()
                            Text(statusText).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                        }
                    }
                    .accessibilityLabel("My WHOOP, \(statusText)").accessibilityIdentifier("openDevice")
                    notificationRow
                }
                .listRowBackground(ZoopStyle.surface)
                Section {
                    NavigationLink(value: Page.server) { Label("Account", systemImage: "person.crop.circle") }
                    Link("Privacy policy", destination: URL(string: "https://zoop.health/docs/data-privacy/")!)
                    Link("Help & support", destination: URL(string: "https://zoop.health/docs/help/")!)
                    NavigationLink(value: Page.advanced) { Label("Advanced", systemImage: "slider.horizontal.3") }
                }
                .listRowBackground(ZoopStyle.surface)
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
            .listSectionSpacing(.compact)
            .zoopScreen()
            .navigationTitle("Profile & settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { closeControl }
            .navigationDestination(for: Page.self) { page in
                Group { switch page {
                case .body: BodyProfileView()
                case .health: AppleHealthView()
                case .ecg: if BuildFeatures.manualECG { ECGView() }
                case .notifications: NotificationSettingsView()
                case .device: DeviceView()
                case .advanced: AdvancedSettingsView()
                case .server: ServerSettingsView()
                case .diagnostics: DiagnosticsView()
                } }.toolbar { closeControl }
            }
            .task { await model.battery.refreshAuthorization() }
            .task(id: photoScope) { await model.photo.load(photoScope, force: true) }
            .sheet(isPresented: $editingPhoto) { ProfilePhotoView(scope: photoScope) }
            .onAppear { if let open, path.isEmpty, open != .ecg || BuildFeatures.manualECG { path = [open] } }
        }
        .tint(ZoopStyle.text)
        .presentationDragIndicator(.visible)
        .presentationBackground(ZoopStyle.background)
    }

    private var closeControl: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(ZoopType.font(size: 16, weight: .medium, relativeTo: .body)).frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Close")
        }
    }

    private var notificationRow: some View {
        NavigationLink(value: Page.notifications) {
            HStack {
                Label("Notifications", systemImage: "bell")
                Spacer()
                Text(authorizationText).foregroundStyle(ZoopStyle.secondary)
            }
        }.accessibilityIdentifier("openNotifications")
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
