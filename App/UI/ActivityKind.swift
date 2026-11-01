import SwiftUI

/// Session types the server detects, each with the one accent it keeps across the app.
enum ActivityKind: String, CaseIterable, Identifiable {
    case walk, resistance, activity

    var id: String { rawValue }

    var name: String {
        switch self {
        case .walk: "Walk"
        case .resistance: "Strength training"
        case .activity: "Activity"
        }
    }

    var longName: String {
        switch self {
        case .walk: "Walk"
        case .resistance: "Strength training"
        case .activity: "Unlabelled activity"
        }
    }

    var icon: String {
        switch self {
        case .walk: "figure.walk"
        case .resistance: "dumbbell.fill"
        case .activity: "bolt.heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .walk: SnoopStyle.steps
        case .resistance: SnoopStyle.load
        case .activity: SnoopStyle.secondary
        }
    }

    /// Unknown server values fall back to the catch-all so nothing is hidden.
    static func named(_ raw: String) -> ActivityKind {
        ActivityKind(rawValue: raw) ?? .activity
    }
}
