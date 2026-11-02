import Foundation

enum TrendRange: String, CaseIterable, Identifiable, Sendable {
    case week = "7 days", month = "30 days", quarter = "90 days", all = "Year"
    var id: String { rawValue }
    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .all: 365
        }
    }
}
