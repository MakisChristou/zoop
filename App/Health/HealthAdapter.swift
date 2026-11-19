import Foundation
import HealthKit
import ZoopHealth

/// HealthKit is confined to this adapter. Only Zoop's source and selected namespace
/// may be reconciled; imported weight is never sent back as a Zoop measurement.
@MainActor
final class HealthAdapter {
    let store = HKHealthStore()
    static let recordKey = "snoop.record"
    static let namespaceKey = "snoop.namespace"
    static let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass)!
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    func type(_ domain: String) -> HKSampleType {
        switch domain {
        case "sleep": HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        case "steps": HKObjectType.quantityType(forIdentifier: .stepCount)!
        case "weight": Self.weightType
        default: HKObjectType.workoutType()
        }
    }
    func canWrite(_ domain: String) -> Bool { available && store.authorizationStatus(for: type(domain)) == .sharingAuthorized }
    func request(steps: Bool, importWeight: Bool, exportWeight: Bool) async throws {
        var writes: Set<HKSampleType> = [type("sleep"), type("workout")]
        if steps { writes.insert(type("steps")) }
        if exportWeight { writes.insert(Self.weightType) }
        let reads: Set<HKObjectType> = importWeight || exportWeight ? [Self.weightType] : []
        try await store.requestAuthorization(toShare: writes, read: reads)
    }
    enum Failure: LocalizedError {
        case unavailable, newerVersion, invalidRecord
        var errorDescription: String? {
            switch self {
            case .unavailable: "Apple Health is unavailable on this device."
            case .newerVersion: "Apple Health has a newer Zoop export. Restore the latest server history before syncing."
            case .invalidRecord: "This recording is incomplete. Try syncing again after analysis finishes."
            }
        }
    }
    func samples(type: HKSampleType, predicate: NSPredicate?) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            store.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            })
        }
    }
    func owned(_ record: HealthRecord, namespace: String) async throws -> [HKSample] {
        try await samples(type: type(record.domain), predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForObjects(withMetadataKey: Self.namespaceKey, allowedValues: [namespace]),
            HKQuery.predicateForObjects(withMetadataKey: Self.recordKey, allowedValues: [record.id])
        ]))
    }
    func existingWeight(on date: Date, calendar: Calendar = .current) async throws -> [HKQuantitySample] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return try await samples(type: Self.weightType, predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate))
            .compactMap { $0 as? HKQuantitySample }.filter { $0.sourceRevision.source != .default() }
    }
    func removeExports(namespace: String) async throws {
        for domain in ["sleep", "workout", "steps", "weight"] {
            let own = try await samples(type: type(domain), predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [HKQuery.predicateForObjects(from: HKSource.default()), HKQuery.predicateForObjects(withMetadataKey: Self.namespaceKey, allowedValues: [namespace])]))
            for start in stride(from: 0, to: own.count, by: 200) { try await store.delete(Array(own[start..<min(start + 200, own.count)])) }
        }
    }
    func removeWeightConflicts(namespace: String) async throws {
        guard canWrite("weight") else { return }
        let own = try await samples(type: Self.weightType, predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [HKQuery.predicateForObjects(from: HKSource.default()), HKQuery.predicateForObjects(withMetadataKey: Self.namespaceKey, allowedValues: [namespace])]))
        var seen: Set<Date> = []
        for row in own {
            let day = Calendar.current.startOfDay(for: row.startDate)
            guard seen.insert(day).inserted else { continue }
            if !(try await existingWeight(on: day)).isEmpty {
                // Only remove our redundant Health copies, never the Zoop history or
                // the external reading. Receipts prevent unchanged re-exports.
                try await store.delete(own.filter { Calendar.current.isDate($0.startDate, inSameDayAs: day) })
            }
        }
    }
    func apply(_ record: HealthRecord, namespace: String, restore: Bool = false) async throws {
        let existing = try await owned(record, namespace: namespace)
        let maximum = existing.compactMap { ($0.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.int64Value }.max() ?? 0
        guard maximum <= record.version else { throw Failure.newerVersion }
        if record.removed {
            if !existing.isEmpty { try await store.delete(existing) }
            return
        }
        if record.domain == "workout" {
            guard record.endTs > record.startTs else { throw Failure.invalidRecord }
            if maximum < record.version || restore { try await saveWorkout(record, namespace: namespace) }
            let wanted = "\(namespace).\(record.id).0"
            let obsolete = existing.filter { $0.metadata?[HKMetadataKeySyncIdentifier] as? String != wanted }
            if !obsolete.isEmpty { try await store.delete(obsolete) }
            return
        }
        let desired = try makeSamples(record, namespace: namespace)
        // A matching version after reinstall is already exported. Do not recreate
        // missing members that the person deliberately deleted in Health.
        if maximum < record.version || restore { if !desired.isEmpty { try await store.save(desired) } }
        let wanted = Set(desired.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String })
        let obsolete = existing.filter { !wanted.contains($0.metadata?[HKMetadataKeySyncIdentifier] as? String ?? "") }
        if !obsolete.isEmpty { try await store.delete(obsolete) }
    }
    /// Builder completion persists the workout, so it must never be followed by save().
    private func saveWorkout(_ record: HealthRecord, namespace: String) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = record.payload.kind == "walk" ? .walking : record.payload.kind == "resistance" ? .traditionalStrengthTraining : .other
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
        do {
            try await builder.beginCollection(at: record.startTs)
            try await builder.addMetadata([
                HKMetadataKeySyncIdentifier: "\(namespace).\(record.id).0",
                HKMetadataKeySyncVersion: NSNumber(value: record.version),
                Self.recordKey: record.id, Self.namespaceKey: namespace
            ])
            try await builder.endCollection(at: record.endTs)
            _ = try await builder.finishWorkout()
        } catch { builder.discardWorkout(); throw error }
    }
    private func makeSamples(_ r: HealthRecord, namespace: String) throws -> [HKSample] {
        func metadata(_ member: String) -> [String: Any] {
            [HKMetadataKeySyncIdentifier: "\(namespace).\(r.id).\(member)", HKMetadataKeySyncVersion: NSNumber(value: r.version), Self.recordKey: r.id, Self.namespaceKey: namespace]
        }
        switch r.domain {
        case "sleep":
            guard let intervals = r.payload.intervals else { throw Failure.invalidRecord }
            return try intervals.enumerated().map { index, interval in
                guard interval.end > interval.start, interval.start >= r.startTs, interval.end <= r.endTs else { throw Failure.invalidRecord }
                return HKCategorySample(type: type("sleep") as! HKCategoryType, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, start: interval.start, end: interval.end, metadata: metadata(String(index)))
            }
        case "steps":
            guard let count = r.payload.count, count > 0, r.endTs > r.startTs else { throw Failure.invalidRecord }
            return [HKQuantitySample(type: type("steps") as! HKQuantityType, quantity: HKQuantity(unit: .count(), doubleValue: Double(count)), start: r.startTs, end: r.endTs, metadata: metadata("0"))]
        case "weight":
            guard let kg = r.payload.kg, kg.isFinite, (20...400).contains(kg) else { throw Failure.invalidRecord }
            return [HKQuantitySample(type: Self.weightType, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg), start: r.startTs, end: r.endTs, metadata: metadata("0"))]
        default: throw Failure.invalidRecord
        }
    }
    /// Read-only preview; no samples are uploaded or written to Health.
    func weightReadings(in range: HealthJournal.Range) async throws -> [WeightReading] {
        try await samples(type: Self.weightType, predicate: HKQuery.predicateForSamples(withStart: range.from, end: range.to, options: .strictStartDate))
            .compactMap(Self.externalWeight)
    }
    nonisolated private static func externalWeight(_ sample: HKSample) -> WeightReading? {
        guard sample.sourceRevision.source != .default(), let sample = sample as? HKQuantitySample else { return nil }
        let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
        guard kg.isFinite, (20...400).contains(kg), sample.startDate <= Date() else { return nil }
        return WeightReading(id: "health:" + sample.uuid.uuidString, measuredAt: sample.startDate, kg: kg, source: "health", sourceName: sample.sourceRevision.source.name)
    }
    struct WeightChanges {
        let readings: [WeightReading]
        let deleted: [String]
        let anchor: Data
        let more: Bool
    }
    func weightChanges(anchor data: Data?, from: Date, to: Date?) async throws -> WeightChanges {
        let anchor = try data.flatMap { try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            store.execute(HKAnchoredObjectQuery(type: Self.weightType, predicate: predicate, anchor: anchor, limit: 200) { _, samples, deleted, anchor, error in
                if let error { continuation.resume(throwing: error); return }
                do {
                    guard let anchor else { throw Failure.unavailable }
                    let readings = (samples ?? []).compactMap(Self.externalWeight)
                    let result = WeightChanges(readings: readings, deleted: (deleted ?? []).map { "health:" + $0.uuid.uuidString }, anchor: try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true), more: (samples?.count ?? 0) + (deleted?.count ?? 0) >= 200)
                    continuation.resume(returning: result)
                } catch { continuation.resume(throwing: error) }
            })
        }
    }
}
