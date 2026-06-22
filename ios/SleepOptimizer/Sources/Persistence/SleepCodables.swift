import Foundation
import SleepEngine

// Shared JSON coders for storing engine value types as blobs inside SwiftData
// `@Model` classes. The engine types stay pure Foundation (just `Codable`); the
// SwiftData models live only in the app target. Encoding as blobs avoids
// flattening ~20 fields into columns and sidesteps SwiftData's awkward handling
// of arrays-of-structs, so engine schema tweaks don't force a store migration.
enum SleepCodables {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decoder.decode(type, from: data)
    }
}
