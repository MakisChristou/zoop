import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreTransferable

/// Downsample before decoding full-size pixels, apply orientation, and encode only
/// the resulting image. EXIF/GPS metadata never enters the upload.
enum ProfilePhotoEncoding {
    static let maxBytes = 256 * 1024
    static let maxPixels = 512
    static func jpeg(from url: URL) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw Failure.invalid }
        return try encode(source)
    }
    static func jpeg(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw Failure.invalid }
        return try encode(source)
    }
    private static func encode(_ source: CGImageSource) throws -> Data {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw Failure.invalid }
        for quality in [0.85, 0.7, 0.5] {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw Failure.invalid }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination), data.length <= maxBytes { return data as Data }
        }
        throw Failure.invalid
    }
    enum Failure: LocalizedError {
        case invalid
        var errorDescription: String? { "This photo couldn’t be prepared. Choose another image." }
    }
}

struct PickedProfilePhoto: Transferable, Sendable {
    let jpeg: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            Self(jpeg: try ProfilePhotoEncoding.jpeg(from: received.file))
        }
    }
}
