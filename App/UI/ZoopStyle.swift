import SwiftUI

/// Shared surfaces and metric colours, resolved in the system's appearance.
enum ZoopStyle {
    static let background = adaptive(light: 0xF2F4F5, dark: 0x0A0A0A)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x171717)
    static let text = adaptive(light: 0x162229, dark: 0xFAFAFA)
    static let secondary = adaptive(light: 0x586871, dark: 0xA3A3A3)
    static let separator = adaptive(light: 0xDCE3E7, dark: 0x303030)
    static let track = adaptive(light: 0xE2E8EC, dark: 0x262626)
    static let load = adaptive(light: 0x006DA8, dark: 0x479EEA)
    static let sleep = adaptive(light: 0x7061B6, dark: 0x9AAAE5)
    static let steps = adaptive(light: 0x08786F, dark: 0x64D3BD)
    static let heartRate = adaptive(light: 0xB74B55, dark: 0xEE8C94)
    static let temperature = adaptive(light: 0x986028, dark: 0xD8AC79)
    static let favourable = adaptive(light: 0x087C38, dark: 0x30DE78)
    static let typical = adaptive(light: 0x865C00, dark: 0xEAC564)
    static let unfavourable = adaptive(light: 0xCC203C, dark: 0xFF5C62)
    static let gutter: CGFloat = 20
    static let radius: CGFloat = 12
    static let sectionTitle: Font = .subheadline.weight(.medium)

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
    func zoopScreen() -> some View {
        background(ZoopStyle.background.ignoresSafeArea())
            .foregroundStyle(ZoopStyle.text)
            .tint(ZoopStyle.text)
            .toolbarBackground(ZoopStyle.background, for: .navigationBar)
    }

    func zoopCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(ZoopStyle.surface, in: RoundedRectangle(cornerRadius: ZoopStyle.radius))
            .contentShape(RoundedRectangle(cornerRadius: ZoopStyle.radius))
    }
}
