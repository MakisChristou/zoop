import Foundation

/// Zoop creates one daily check-in. Imported history remains owned by its source.
public enum WeightEntryPolicy {
    public enum Failure: LocalizedError, Equatable {
        case alreadyLogged, importedReading
        public var errorDescription: String? {
            switch self {
            case .alreadyLogged: "Weight is already logged for this day. Tap it to edit."
            case .importedReading: "Edit this measurement in Apple Health."
            }
        }
    }

    public static func validate(_ candidate: WeightReading, existing: [WeightReading], calendar: Calendar = .current) throws {
        let original = existing.first { $0.id == candidate.id }
        guard candidate.source == "snoop", original?.source != "health" else { throw Failure.importedReading }
        if candidate.removed { return }
        // Editing an existing observation does not create a second check-in.
        // Leave any pre-existing/imported duplicates intact.
        if let original, calendar.isDate(original.measuredAt, inSameDayAs: candidate.measuredAt) { return }
        if existing.contains(where: { !$0.removed && $0.id != candidate.id && calendar.isDate($0.measuredAt, inSameDayAs: candidate.measuredAt) }) {
            throw Failure.alreadyLogged
        }
    }
}
