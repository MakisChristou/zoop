public enum ProtocolError: Error, Equatable {
    case tooShort(length: Int)
    case notFormat1(start: UInt8, format: UInt8)
    case lengthMismatch(declared: Int, actual: Int)
    case unaligned
    case headerCRC
    case bodyCRC
    case recordLength(layout: UInt8, expected: Int, actual: Int)
    case outOfBounds(offset: Int)
    case badToken(length: Int)
}
