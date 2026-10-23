import Foundation

/// GATT identifiers for the WHOOP 5.0 / MG custom service.
public enum GATT {
    public static let service = "FD4B0001-CCE1-4033-93CE-002D5875F58A"
    public static let commandWrite = "FD4B0002-CCE1-4033-93CE-002D5875F58A"
    public static let notifyCommandResponse = "FD4B0003-CCE1-4033-93CE-002D5875F58A"
    public static let notifyEvents = "FD4B0004-CCE1-4033-93CE-002D5875F58A"
    public static let notifyData = "FD4B0005-CCE1-4033-93CE-002D5875F58A"
    public static let notifyDiagnostics = "FD4B0007-CCE1-4033-93CE-002D5875F58A"

    public static let notifyCharacteristics = [
        notifyCommandResponse, notifyEvents, notifyData, notifyDiagnostics,
    ]

    /// Standard services, readable without a bond.
    public static let deviceInformationService = "180A"
    public static let modelNumberString = "2A24"
    public static let serialNumberString = "2A25"
    public static let heartRateService = "180D"
    public static let heartRateMeasurement = "2A37"

    public static let serialPrefixMG = "5AM"
    public static let serialPrefix50 = "5AG"
}
