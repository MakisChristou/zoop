import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import Zoop

@MainActor final class ProfilePhotoTests: XCTestCase {
    private func image(_ color: UIColor = .blue, size: CGSize = .init(width: 32, height: 16)) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.9)!
    }
    private func disk() -> ProfilePhotoDisk {
        ProfilePhotoDisk(folder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }
    private func scope(_ device: String = "TEST", connection: String = "test") -> ProfilePhotoStore.Scope { .init(device: device, connection: connection) }

    func testPreparedPhotoIsSmallOrientedAndHasNoGPS() throws {
        let original = image(size: .init(width: 2048, height: 1024))
        let source = CGImageSourceCreateWithData(original as CFData, nil)!
        let pixels = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, pixels, [kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.0, kCGImagePropertyGPSLatitudeRef: "N"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        try (data as Data).write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let result = try ProfilePhotoEncoding.jpeg(from: file)
        XCTAssertLessThanOrEqual(result.count, ProfilePhotoEncoding.maxBytes)
        let encoded = CGImageSourceCreateWithData(result as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(encoded, 0, nil)! as NSDictionary
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 256)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 512)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertThrowsError(try ProfilePhotoEncoding.jpeg(from: Data("bad image".utf8)))
    }
    func testPhotoRoundTripAndOfflineCacheSurviveStoreRecreation() async throws {
        let data = image(), disk = disk()
        var server: Data?, methods: [String] = []
        let store = ProfilePhotoStore(disk: disk, remote: { _, method, photo in
            methods.append(method)
            if method == "PUT" { server = photo }
            if method == "DELETE" { server = nil }
            return server
        })
        await store.load(scope())
        XCTAssertNil(store.image(for: scope()))
        try await store.save(data, for: scope())
        XCTAssertNotNil(store.image(for: scope()))
        let offline = ProfilePhotoStore(disk: disk, remote: { _, _, _ in throw URLError(.notConnectedToInternet) })
        await offline.load(scope()); XCTAssertNotNil(offline.image(for: scope()))
        await offline.load(scope(connection: "another account")); XCTAssertNil(offline.image(for: scope(connection: "another account")))
        try await store.save(nil, for: scope()); XCTAssertNil(store.image(for: scope()))
        let cached = await disk.read(scope().diskKey); XCTAssertNil(cached)
        XCTAssertEqual(methods, ["GET","PUT","DELETE"])
    }
    func testLatePhotoCannotReplaceAnotherDeviceAndFailedSaveKeepsOldPhoto() async throws {
        let blue = image(), red = image(.red)
        let store = ProfilePhotoStore(disk: disk(), remote: { device, method, _ in
            if method == "PUT" { throw URLError(.notConnectedToInternet) }
            if device == "OLD" { try? await Task.sleep(for: .milliseconds(80)); return blue }
            return red
        })
        let old = Task { await store.load(self.scope("OLD")) }
        try await Task.sleep(for: .milliseconds(10)); await store.load(scope("NEW")); await old.value
        XCTAssertNil(store.image(for: scope("OLD"))); XCTAssertNotNil(store.image(for: scope("NEW")))
        let previous = store.image(for: scope("NEW"))
        do { try await store.save(blue, for: scope("NEW")); XCTFail("Expected save failure") } catch { }
        XCTAssertTrue(store.image(for: scope("NEW")) === previous)
        XCTAssertFalse(store.saving)
    }
}
