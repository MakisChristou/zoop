import Foundation

extension SnoopAPI {
    static func profilePhoto(device: String, method: String = "GET", jpeg: Data? = nil) async throws -> Data? {
        var request = try request("v1/devices/\(device)/profile/photo")
        request.httpMethod = method; request.httpBody = jpeg
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if jpeg != nil { request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw Failure.http(0) }
        if method == "GET", http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw Failure.http(http.statusCode) }
        if http.statusCode == 204 { return nil }
        guard data.count <= ProfilePhotoEncoding.maxBytes, http.mimeType == "image/jpeg" else { throw ProfilePhotoEncoding.Failure.invalid }
        return data
    }
}
