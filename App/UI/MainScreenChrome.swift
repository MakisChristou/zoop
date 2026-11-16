import SwiftUI

/// Compact header shared by the main tabs. Detail pages retain native navigation.
struct MainScreenChrome: ViewModifier {
    let title: String
    var subtitle: String?
    private struct Request: Identifiable {
        let id = UUID()
        let page: ProfileSheet.Page?
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var model
    @State private var request: Request?

    func body(content: Content) -> some View {
        chrome(content)
            .sheet(item: $request) { ProfileSheet(open: $0.page) }
            .onAppear(perform: applyDemoRoute)
            .task(id: PhotoRefresh(scope: photoScope, active: scenePhase == .active)) {
                if scenePhase == .active { await model.photo.load(photoScope) }
            }
    }

    @ViewBuilder private func chrome(_ content: Content) -> some View {
        if typeSize.isAccessibilitySize {
            content
                .snoopScreen()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        ConnectionStatusLabel(compact: true) { request = Request(page: .device) }
                        Button { request = Request(page: nil) } label: {
                            ProfileAvatar()
                        }
                        .accessibilityLabel("Profile and settings")
                        .accessibilityIdentifier("openProfile")
                    }
                }
        } else {
            content
            .snoopScreen()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let subtitle { Text(subtitle).font(.caption).foregroundStyle(SnoopStyle.secondary) }
                        Text(title).font(.title.weight(.bold)).accessibilityAddTraits(.isHeader)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 10) {
                        ConnectionStatusLabel { request = Request(page: .device) }
                        Button { request = Request(page: nil) } label: {
                            ProfileAvatar()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Profile and settings")
                        .accessibilityIdentifier("openProfile")
                    }
                }
                .padding(.horizontal, SnoopStyle.gutter)
                .padding(.top, 8).padding(.bottom, 18)
                .foregroundStyle(SnoopStyle.text)
                .background(SnoopStyle.background)
            }
        }
    }

    private func applyDemoRoute() {
        #if targetEnvironment(simulator)
        switch UserDefaults.standard.string(forKey: "demoScreen") {
        case "profile": request = Request(page: nil)
        case "device": request = Request(page: .device)
        case "editprofile": request = Request(page: .body)
        case "ecg": request = Request(page: .ecg)
        default: break
        }
        #endif
    }
    private struct PhotoRefresh: Equatable { let scope: ProfilePhotoStore.Scope; let active: Bool }
    private var photoScope: ProfilePhotoStore.Scope { .init(device: model.strap.serial, connection: Settings.connectionID) }
}

extension View {
    func mainScreenChrome(_ title: String, subtitle: String? = nil) -> some View {
        modifier(MainScreenChrome(title: title, subtitle: subtitle))
    }
}
