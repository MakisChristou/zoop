import SwiftUI

@main
struct ZoopApp: App {
    @State private var model: AppModel
    private let storageProtectionFailed: Bool

    init() {
        let protected: Bool
        do { try DeviceDataProtection.prepare(); protected = true }
        catch { protected = false }
        storageProtectionFailed = !protected
        _model = State(initialValue: AppModel(servicesEnabled: protected))
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-resetAuthTest") { try? Settings.clear() }
        #endif
        UISegmentedControl.appearance().setTitleTextAttributes([.font: UIFont(name: "Geist-Medium", size: 12) ?? UIFont.systemFont(ofSize: 12)], for: .normal)
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.25, alpha: 1) : UIColor.white }
        UISegmentedControl.appearance().backgroundColor = UIColor(ZoopStyle.surface)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.titleTextAttributes = [.font: UIFont(name: "Geist-Medium", size: 16) ?? UIFont.systemFont(ofSize: 16)]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            AccountRootView(storageProtectionFailed: storageProtectionFailed)
                .environment(model)
                .font(ZoopType.body)
        }
    }
}

/// Own session state in the view so credential changes rebuild the navigation gate.
private struct AccountRootView: View {
    @Environment(AppModel.self) private var model
    let storageProtectionFailed: Bool
    @State private var connection = Settings.connectionID
    @State private var signedIn = Settings.isConfigured

    var body: some View {
        Group {
            if storageProtectionFailed {
                ContentUnavailableView("Storage unavailable", systemImage: "lock", description: Text("Unlock your iPhone and reopen Zoop to protect its saved health data."))
                    .zoopScreen()
            } else if model.accountErasureInProgress {
                VStack(spacing: 20) {
                    if let error = model.accountErasureError {
                        Text(error)
                        Button("Retry") { Task { await model.resumeAccountErasure() } }
                    } else { ProgressView("Deleting account") }
                }.padding().zoopScreen()
            } else if model.isOnboarded && signedIn {
                if !model.strap.serial.isEmpty && !Settings.permitsDevice(model.strap.serial) {
                    NavigationStack {
                        VStack(spacing: 20) {
                            ContentUnavailableView("Device not assigned", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("Ask your server administrator to assign this strap to your account, then sign in again."))
                            NavigationLink("Server connection") { ServerSettingsView() }
                        }.zoopScreen()
                    }
                } else { RootView().id(connection) }
            } else if model.isOnboarded {
                NavigationStack { Form { ServerSignInSection() }.scrollContentBackground(.hidden).zoopScreen().navigationTitle("Sign in to Zoop") }
            } else {
                OnboardingView()
            }
        }
        // Signing in must not recreate first-run setup halfway through its flow.
        .id(model.isOnboarded ? connection : "first-run-setup")
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in connection = Settings.connectionID; signedIn = Settings.isConfigured }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in connection = Settings.connectionID; signedIn = Settings.isConfigured }
    }
}
