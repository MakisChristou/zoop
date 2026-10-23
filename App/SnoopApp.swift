import SwiftUI

@main
struct SnoopApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if model.isOnboarded {
                    RootView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(model)
            .preferredColorScheme(.dark)
        }
    }
}
