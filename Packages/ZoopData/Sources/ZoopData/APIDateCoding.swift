import Foundation

/// Formatters belong to one decoding pass; no mutable formatter is shared across tasks.
public enum APIDateCoding {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let value = fractional.date(from: text) ?? whole.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid timestamp")
            }
            return value
        }
        return decoder
    }
}
