import Foundation
import ZoopProtocol

struct ECGDevice: Equatable {
    let serial: String
    let firmware: String?
    let isMG: Bool
}

@MainActor protocol ECGTransport: AnyObject {
    var ecgDevice: ECGDevice? { get }
    func performECG(_ operation: ECGOperation) async throws
}

enum ECGTransportError: LocalizedError {
    case disconnected, busy, storage, timeout(UInt8), refused(UInt8, String)
    var errorDescription: String? {
        switch self {
        case .disconnected: "WHOOP disconnected. Reconnect before trying again."
        case .busy: "Another ECG command is still finishing."
        case .storage: "Zoop cannot safely store incoming data. Free some space and try again."
        case let .timeout(code): "WHOOP did not acknowledge ECG command \(code)."
        case let .refused(code, result): "WHOOP refused ECG command \(code): \(result)."
        }
    }
}
