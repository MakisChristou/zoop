import SwiftUI

enum TrendMetric: String, CaseIterable, Identifiable, Sendable {
    case sleep = "Sleep", restingHr = "Resting HR", hrv = "HRV", breathing = "Breathing", skinTemp = "Skin temp", steps = "Steps", efficiency = "Efficiency"
    var id: String { rawValue }
    var unit: String {
        switch self {
        case .sleep: "h"
        case .restingHr: "bpm"
        case .hrv: "ms"
        case .breathing: "/min"
        case .skinTemp: "°C"
        case .steps: ""
        case .efficiency: "%"
        }
    }
    var decimals: Int {
        switch self {
        case .sleep, .breathing, .skinTemp: 1
        default: 0
        }
    }
    var color: Color {
        switch self {
        case .sleep: SnoopStyle.sleep
        case .restingHr: SnoopStyle.heartRate
        case .hrv: SnoopStyle.sleep
        case .breathing: SnoopStyle.steps
        case .skinTemp: SnoopStyle.temperature
        case .steps: SnoopStyle.steps
        case .efficiency: SnoopStyle.sleep
        }
    }
    /// Whether a higher value is good, for the delta colour.
    var higherIsBetter: Bool? {
        switch self {
        case .sleep, .hrv, .efficiency: true
        case .restingHr: false
        default: nil
        }
    }
}
