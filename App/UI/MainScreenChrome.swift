import SwiftUI

/// Compact header shared by the five tabs. Detail pages retain native navigation.
struct MainScreenChrome: ViewModifier {
    let title: String
    var subtitle: String?
    private struct Request: Identifiable {
        let id = UUID()
        let page: ProfileSheet.Page?
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var request: Request?

    func body(content: Content) -> some View {
        chrome(content)
            .sheet(item: $request) { ProfileSheet(open: $0.page) }
            .onAppear(perform: applyDemoRoute)
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
                            Label("Profile and settings", systemImage: "person")
                        }
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
                            Image(systemName: "person").font(.body.weight(.medium))
                                .frame(width: 44, height: 44)
                                .background(SnoopStyle.surface, in: Circle())
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
        default: break
        }
        #endif
    }
}

extension View {
    func mainScreenChrome(_ title: String, subtitle: String? = nil) -> some View {
        modifier(MainScreenChrome(title: title, subtitle: subtitle))
    }
}
