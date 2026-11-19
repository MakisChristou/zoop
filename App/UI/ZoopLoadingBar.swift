import SwiftUI

/// Unknown-duration work stays indeterminate; measured imports keep native progress.
struct ZoopLoadingBar: View {
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travelling = false

    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(ZoopStyle.secondary.opacity(0.15))
                .overlay(alignment: .leading) {
                    Capsule().fill(ZoopStyle.secondary)
                        .frame(width: geometry.size.width * 0.3)
                        .offset(x: travelling && !reduceMotion ? geometry.size.width * 0.7 : 0)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: travelling)
        }
        .frame(height: 3)
        .onAppear { travelling = true }
        .onDisappear { travelling = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("loadingIndicator")
    }
}

extension View {
    func zoopLoading(_ active: Bool, label: String) -> some View {
        overlay(alignment: .top) {
            if active {
                ZoopLoadingBar(label: label)
                    .padding(.horizontal, ZoopStyle.gutter)
                    .allowsHitTesting(false)
            }
        }
    }
}
