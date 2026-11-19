/// Explicit ECG controls; generation, live delivery and history are separate gates.
public enum ECGOperation: Equatable, Sendable {
    case wrist(ECGWrist)
    case generation(Bool)
    case rawLive(Bool)
    case filteredLive(Bool)
    case saveRaw(Bool)
    case saveFiltered(Bool)

    public var command: Command {
        switch self {
        case .wrist: .ecgWrist
        case .generation: .ecgGeneration
        case .rawLive: .ecgRawLive
        case .filteredLive: .ecgFilteredLive
        case .saveRaw: .ecgSaveRaw
        case .saveFiltered: .ecgSaveFiltered
        }
    }

    public func frame(sequence: UInt8) -> [UInt8] {
        let value: UInt8
        switch self {
        case let .wrist(wrist): value = wrist.wireValue
        case let .generation(start): value = start ? 2 : 1
        case let .rawLive(on), let .filteredLive(on), let .saveRaw(on), let .saveFiltered(on): value = on ? 1 : 0
        }
        return Command.build(command, sequence: sequence, args: [1, value])
    }
}
