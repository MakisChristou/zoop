/// WHOOP 5/MG accessory record. Presence does not mean the strap is charging.
/// Identity is used only to keep readings and reminder state separate across packs.
public struct BatteryPackInfo: Equatable {
    public let present: Bool
    public let identifier: [UInt8]
    public let rawCharge: UInt16
    public var percent: Double? {
        present && rawCharge <= 1000 ? Double(rawCharge) / 10 : nil
    }

    private static let identifierOffset = 1
    private static let identifierLength = 6
    private static let chargeOffset = 23
    private static let minimumRecordLength = 25

    init?(record: [UInt8]) {
        guard record.count >= Self.minimumRecordLength, record[0] <= 1 else { return nil }
        present = record[0] == 1
        identifier = Array(record[Self.identifierOffset..<(Self.identifierOffset + Self.identifierLength)])
        rawCharge = UInt16(record[Self.chargeOffset]) | UInt16(record[Self.chargeOffset + 1]) << 8
    }
}
