import OSLog

/// Instruments intervals contain operation names only, never health data or credentials.
public enum PerformanceTrace {
    private static let signposter = OSSignposter(subsystem: "snoop", category: "performance")
    public static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try work()
    }
}
