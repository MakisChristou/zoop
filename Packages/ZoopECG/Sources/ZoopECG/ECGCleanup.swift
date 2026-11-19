import ZoopProtocol

/// Durable intent is written before issuing each possibly mutating command.
public struct ECGCleanup: Codable, Equatable, Sendable {
    public let device: String
    public var generation = false
    public var rawLive = false
    public var filteredLive = false
    public init(device: String) { self.device = device }
    public var isEmpty: Bool { !generation && !rawLive && !filteredLive }
    public var operations: [ECGOperation] {
        var result: [ECGOperation] = []
        if generation { result.append(.generation(false)) }
        if filteredLive { result.append(.filteredLive(false)) }
        if rawLive { result.append(.rawLive(false)) }
        return result
    }
    public mutating func acknowledge(_ operation: ECGOperation) {
        switch operation {
        case .generation(false): generation = false
        case .filteredLive(false): filteredLive = false
        case .rawLive(false): rawLive = false
        default: break
        }
    }
}
