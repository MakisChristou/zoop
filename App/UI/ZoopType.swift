import SwiftUI

/// Measured from the reference: Geist 14/20 labels, 11/16 axes, 20-point readouts.
/// Relative styles retain Dynamic Type instead of baking screenshots into fixed text.
enum ZoopType {
    static func font(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(face(weight), size: size, relativeTo: style)
    }
    static func fixed(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(face(weight), fixedSize: size)
    }
    static func face(_ weight: Font.Weight) -> String {
        weight == .bold || weight == .semibold ? "Geist-SemiBold" : weight == .medium ? "Geist-Medium" : "Geist-Regular"
    }
    static let largeTitle = font(size: 24, weight: .semibold, relativeTo: .largeTitle)
    static let title = font(size: 20, weight: .semibold, relativeTo: .title)
    static let title2 = font(size: 20, weight: .medium, relativeTo: .title2)
    static let title3 = font(size: 16, weight: .medium, relativeTo: .title3)
    static let headline = font(size: 14, weight: .medium, relativeTo: .headline)
    static let subheadline = font(size: 14, relativeTo: .subheadline)
    static let body = font(size: 16)
    static let callout = font(size: 14, relativeTo: .callout)
    static let footnote = font(size: 12, relativeTo: .footnote)
    static let caption = font(size: 12, relativeTo: .caption)
    static let caption2 = font(size: 11, relativeTo: .caption2)
}
