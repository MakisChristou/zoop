import SwiftUI

struct ECGActionStyle: ButtonStyle {
    var primary = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 28).padding(12)
            .foregroundStyle(primary ? (scheme == .dark ? ZoopStyle.background : Color.white) : ZoopStyle.text)
            .background(primary ? ZoopStyle.load : ZoopStyle.surface, in: RoundedRectangle(cornerRadius: ZoopStyle.radius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
