import SwiftUI

/// Compact header shared by the main tabs. Detail pages retain native navigation.
struct MainScreenChrome: ViewModifier {
    let title: String
    var subtitle: String?
    var detail = false
    private struct Request: Identifiable {
        let id = UUID()
        let page: ProfileSheet.Page?
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var model
    @State private var request: Request?

    @ViewBuilder func body(content: Content) -> some View {
        if detail {
            content.zoopScreen()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
        } else {
            chrome(content)
                .sheet(item: $request) { ProfileSheet(open: $0.page) }
                .onAppear(perform: applyDemoRoute)
                .task(id: PhotoRefresh(scope: photoScope, active: scenePhase == .active)) {
                    if scenePhase == .active { await model.photo.load(photoScope, force: true) }
                }
        }
    }

    @ViewBuilder private func chrome(_ content: Content) -> some View {
        if typeSize.isAccessibilitySize {
            content
                .zoopScreen()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        ConnectionStatusLabel(compact: true) { request = Request(page: .device) }
                        Button { request = Request(page: nil) } label: {
                            ProfileAvatar(size: 32).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Profile and settings")
                        .accessibilityIdentifier("openProfile")
                    }
                }
        } else {
            content
            .zoopScreen()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let subtitle { Text(subtitle).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary) }
                        Text(title == "Today" ? "zoop" : title).font(ZoopType.font(size: 16, weight: .medium, relativeTo: .title3)).accessibilityAddTraits(.isHeader)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 10) {
                        ConnectionStatusLabel { request = Request(page: .device) }
                        Button { request = Request(page: nil) } label: {
                            ProfileAvatar(size: 32).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Profile and settings")
                        .accessibilityIdentifier("openProfile")
                    }
                }
                .padding(.horizontal, ZoopStyle.gutter)
                .padding(.top, 4).padding(.bottom, 8)
                .foregroundStyle(ZoopStyle.text)
                .background(ZoopStyle.background)
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
    private var photoScope: ProfilePhotoStore.Scope { .init(device: model.dataDevice, connection: Settings.connectionID) }
}

extension View {
    func mainScreenChrome(_ title: String, subtitle: String? = nil, detail: Bool = false) -> some View {
        modifier(MainScreenChrome(title: title, subtitle: subtitle, detail: detail))
    }
}
