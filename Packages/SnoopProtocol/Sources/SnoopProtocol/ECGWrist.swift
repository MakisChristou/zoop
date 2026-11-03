/// Revision-1 ECG wrist values. These are not a zero/one boolean.
public enum ECGWrist: String, Codable, CaseIterable, Sendable {
    case left, right
    public var wireValue: UInt8 { self == .right ? 1 : 2 }
}
