import SwiftUI

/// Unknown-duration work stays indeterminate; measured imports keep native progress.
struct ZoopLoadingBar: View {
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        // Draw motion inside a fixed canvas. A repeating view animation can also
        // interpolate layout changes when navigation or safe-area geometry changes.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let track = CGRect(origin: .zero, size: size)
                context.fill(Path(roundedRect: track, cornerRadius: size.height / 2),
                             with: .color(ZoopStyle.secondary.opacity(0.15)))
                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                let progress = reduceMotion ? 0.5 : (1 - cos(phase * 2 * .pi)) / 2
                let segment = CGRect(x: size.width * 0.7 * progress, y: 0,
                                     width: size.width * 0.3, height: size.height)
                context.fill(Path(roundedRect: segment, cornerRadius: size.height / 2),
                             with: .color(ZoopStyle.secondary))
            }
        }
        .frame(height: 3)
        .clipped()
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("loadingIndicator")
    }
}

extension View {
    func zoopLoading(_ active: Bool, label: String) -> some View {
        overlay(alignment: .top) {
            Group {
                if active {
                    ZoopLoadingBar(label: label)
                        .padding(.horizontal, ZoopStyle.gutter)
                        .allowsHitTesting(false)
                        .transition(.identity)
                }
            }
            .transaction { $0.animation = nil }
        }
    }
}
