import SwiftUI

@main
struct SnoopApp: App {
    @State private var model = AppModel()

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
        }
    }
}
