import SwiftUI

/// Only status and comparison text use these colours; surfaces stay neutral.
enum InsightTone {
    static func color(_ signal: String?) -> Color {
        switch signal {
        case "good", "favourable": SnoopStyle.favourable
        case "average", "mixed", "usual": SnoopStyle.typical
        case "low", "unfavourable": SnoopStyle.unfavourable
        default: SnoopStyle.secondary
        }
    }
}
