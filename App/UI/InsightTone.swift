import SwiftUI

/// Only status and comparison text use these colours; surfaces stay neutral.
enum InsightTone {
    static func color(_ signal: String?) -> Color {
        switch signal {
        case "good", "favourable": ZoopStyle.favourable
        case "average", "mixed", "usual": ZoopStyle.typical
        case "low", "unfavourable": ZoopStyle.unfavourable
        default: ZoopStyle.secondary
        }
    }
}
