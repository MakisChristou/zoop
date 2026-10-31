import SwiftUI

/// The header every main tab shares: strap status on the leading side, the profile
/// button on the trailing side, and the profile sheet they both open.
struct MainScreenChrome: ViewModifier {
    /// What to show in the sheet; a value presents it, nil dismisses it.
    private struct Request: Identifiable {
        let id = UUID()
        let page: ProfileSheet.Page?
    }

    @State private var request: Request?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionStatusLabel { request = Request(page: .device) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { request = Request(page: nil) } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                            .accessibilityLabel("Profile and settings")
                    }
                }
            }
            .sheet(item: $request) { ProfileSheet(open: $0.page) }
            .onAppear(perform: applyDemoRoute)
    }

    /// Simulator screenshots: `-demoScreen profile` or `device` opens the sheet.
    private func applyDemoRoute() {
        #if targetEnvironment(simulator)
        switch UserDefaults.standard.string(forKey: "demoScreen") {
        case "profile": request = Request(page: nil)
        case "device": request = Request(page: .device)
        default: break
        }
        #endif
    }
}

extension View {
    /// Status label, profile button and profile sheet, for a main tab's navigation bar.
    func mainScreenChrome() -> some View {
        modifier(MainScreenChrome())
    }
}
