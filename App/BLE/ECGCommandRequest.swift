import Foundation

/// Only one ECG command is in flight; ACKs are matched to its origin sequence.
@MainActor final class ECGCommandRequest {
    let id: UUID
    let command: UInt8
    let sequence: UInt8
    let continuation: CheckedContinuation<Void, Error>
    var timeout: Task<Void, Never>?
    init(id: UUID, command: UInt8, sequence: UInt8, continuation: CheckedContinuation<Void, Error>) {
        self.id = id; self.command = command; self.sequence = sequence; self.continuation = continuation
    }
}
