import SwiftUI

@main
struct ZoopApp: App {
    @State private var model = AppModel()

    init() {
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
                if model.isOnboarded {
                    RootView()
                } else {
                    OnboardingView()
                }
            }
            .environment(model)
            .font(ZoopType.body)
        }
    }
}
