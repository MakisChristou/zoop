import SwiftUI

@main
struct ZoopApp: App {
    @State private var model = AppModel()
    @State private var connection = Settings.connectionID

    init() {
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
            Group {
                if model.isOnboarded && Settings.isConfigured {
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
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in connection = Settings.connectionID }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in connection = Settings.connectionID }
            .environment(model)
            .font(ZoopType.body)
        }
    }
}
