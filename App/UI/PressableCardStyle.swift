import SwiftUI

/// Card links press like buttons: a 0.96 scale and a touch less opacity, 150 ms out,
/// interruptible. The chevron on the card is the static cue; this is only feedback.
/// With Reduce Motion on, only the opacity changes.
struct PressableCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
