import Foundation

/// Value-typed parse styles avoid sharing mutable formatters across decoding tasks.
public enum APIDateCoding {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            let whole = Date.ISO8601FormatStyle()
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let value = (try? fractional.parse(text)) ?? (try? whole.parse(text)) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid timestamp")
            }
            return value
        }
        return decoder
    }
}
