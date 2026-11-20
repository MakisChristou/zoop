import SwiftUI

enum RecoveryTone {
    static func color(_ reading: RecoveryReading?) -> Color {
        guard reading?.displayedScore != nil else { return ZoopStyle.secondary }
        switch reading?.band {
        case "high": return ZoopStyle.favourable
        case "moderate": return ZoopStyle.typical
        case "low": return ZoopStyle.unfavourable
        default: return ZoopStyle.secondary
        }
    }
}
