import SwiftUI

/// Shared surfaces and metric colours, resolved in the system's appearance.
enum SnoopStyle {
    static let background = adaptive(light: 0xF2F4F5, dark: 0x11191D)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1B252B)
    static let text = adaptive(light: 0x162229, dark: 0xF3F6F8)
    static let secondary = adaptive(light: 0x586871, dark: 0xA7B4BC)
    static let separator = adaptive(light: 0xDCE3E7, dark: 0x303C43)
    static let track = adaptive(light: 0xE2E8EC, dark: 0x35434D)
    static let load = adaptive(light: 0x006DA8, dark: 0x27AAFF)
    static let sleep = adaptive(light: 0x7061B6, dark: 0xB0A3E5)
    static let steps = adaptive(light: 0x08786F, dark: 0x64D3BD)
    static let heartRate = adaptive(light: 0xB74B55, dark: 0xEE8C94)
    static let temperature = adaptive(light: 0x986028, dark: 0xD8AC79)
    static let favourable = adaptive(light: 0x137848, dark: 0x79D6A1)
    static let typical = adaptive(light: 0x865C00, dark: 0xEAC564)
    static let unfavourable = adaptive(light: 0xB43C50, dark: 0xF08F9E)
    static let gutter: CGFloat = 20
    static let radius: CGFloat = 16

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

extension View {
    func snoopScreen() -> some View {
        background(SnoopStyle.background.ignoresSafeArea())
            .foregroundStyle(SnoopStyle.text)
            .toolbarBackground(SnoopStyle.background, for: .navigationBar)
    }

    func snoopCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
            .contentShape(RoundedRectangle(cornerRadius: SnoopStyle.radius))
    }
}
