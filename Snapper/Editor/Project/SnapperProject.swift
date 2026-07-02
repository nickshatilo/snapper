import CoreGraphics
import Foundation

struct SnapperProject: Codable {
    var version: Int = 1
    var originalImageFilename: String = "original.png"
    var canvasWidth: Int
    var canvasHeight: Int
    var annotations: [CodableAnnotation]
    var background: BackgroundTemplate?
    var createdDate: Date
    var modifiedDate: Date

    struct CodableAnnotation: Codable {
        var type: ToolType
        var properties: [String: AnyCodable]
    }
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable can't decode this value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let doubleVal = value as? Double {
            try container.encode(doubleVal)
        } else if let cgFloatVal = value as? CGFloat {
            // CGFloat is a distinct type: `as? Double` fails for it, which
            // silently dropped every geometry property.
            try container.encode(Double(cgFloatVal))
        } else if let floatVal = value as? Float {
            try container.encode(Double(floatVal))
        } else if let stringVal = value as? String {
            try container.encode(stringVal)
        } else if let boolVal = value as? Bool {
            try container.encode(boolVal)
        } else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "AnyCodable can't encode \(type(of: value))"
                )
            )
        }
    }
}
