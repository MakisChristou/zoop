import Foundation

/// Health recordings and cached measurements stay in this device's app container.
/// This includes Preferences because existing installs kept daily summaries there.
enum DeviceDataProtection {
    static func prepare(library: URL? = nil) throws {
        var folder = try library ?? FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        // Existing support files remain in place; no recordings are migrated or removed.
        let support = folder.appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var protected = support
        try protected.setResourceValues(values)
        let preferences = folder.appendingPathComponent("Preferences", isDirectory: true)
        try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
        var excluded = preferences
        try excluded.setResourceValues(values)
    }
}
