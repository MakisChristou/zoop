import SwiftUI

/// Charge-level colors are shared by the tab and the connection indicator.
enum BatteryColors {
    static let healthy = Color.green
    static let low = Color.yellow
    static let critical = Color.red
    static let flow = Color.green

    static func level(_ percent: Double?) -> Color {
        guard let percent else { return .secondary }
        switch percent {
        case ...5: return critical
        case ...20: return low
        default: return healthy
        }
    }
}
