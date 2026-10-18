import Foundation

public enum Handedness: String, Codable, Equatable, Sendable {
    case left
    case right
}

public enum MeasurementUnits: String, Codable, Equatable, Sendable {
    case millimeters
}

public struct PalmMeasurements: Codable, Equatable, Sendable {
    public let widthMm: Double?
    public let lengthMm: Double?
    public let thicknessMm: Double?

    public init(widthMm: Double?, lengthMm: Double?, thicknessMm: Double?) {
        self.widthMm = widthMm
        self.lengthMm = lengthMm
        self.thicknessMm = thicknessMm
    }

    private enum CodingKeys: String, CodingKey {
        case widthMm
        case lengthMm
        case thicknessMm
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        widthMm = try container.decode(Double?.self, forKey: .widthMm)
        lengthMm = try container.decode(Double?.self, forKey: .lengthMm)
        thicknessMm = try container.decode(Double?.self, forKey: .thicknessMm)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(widthMm, forKey: .widthMm)
        try container.encode(lengthMm, forKey: .lengthMm)
        try container.encode(thicknessMm, forKey: .thicknessMm)
    }
}

public struct FingerMeasurements: Codable, Equatable, Sendable {
    public let segmentsMm: [Double]
    public let diameterMm: Double?

    public init(segmentsMm: [Double], diameterMm: Double?) {
        self.segmentsMm = segmentsMm
        self.diameterMm = diameterMm
    }

    private enum CodingKeys: String, CodingKey {
        case segmentsMm
        case diameterMm
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        segmentsMm = try container.decode([Double].self, forKey: .segmentsMm)
        diameterMm = try container.decode(Double?.self, forKey: .diameterMm)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(segmentsMm, forKey: .segmentsMm)
        try container.encode(diameterMm, forKey: .diameterMm)
    }
}

public struct FingerMeasurementSet: Codable, Equatable, Sendable {
    public let index: FingerMeasurements
    public let middle: FingerMeasurements
    public let ring: FingerMeasurements
    public let pinky: FingerMeasurements
    public let thumb: FingerMeasurements

    public init(
        index: FingerMeasurements,
        middle: FingerMeasurements,
        ring: FingerMeasurements,
        pinky: FingerMeasurements,
        thumb: FingerMeasurements
    ) {
        self.index = index
        self.middle = middle
        self.ring = ring
        self.pinky = pinky
        self.thumb = thumb
    }
}

public struct HandMeasurements: Codable, Equatable, Sendable {
    public let palm: PalmMeasurements
    public let fingers: FingerMeasurementSet

    public init(palm: PalmMeasurements, fingers: FingerMeasurementSet) {
        self.palm = palm
        self.fingers = fingers
    }
}

public struct LandmarkMeasurement: Codable, Equatable, Sendable {
    public let xMm: Double
    public let yMm: Double
    public let zMm: Double
    public let confidence: Double

    public init(xMm: Double, yMm: Double, zMm: Double, confidence: Double) {
        self.xMm = xMm
        self.yMm = yMm
        self.zMm = zMm
        self.confidence = confidence
    }
}

public struct CaptureCoverage: Codable, Equatable, Sendable {
    public let requiredViews: [String]
    public let capturedViews: [String]
    public let fraction: Double

    public init(requiredViews: [String], capturedViews: [String], fraction: Double) {
        self.requiredViews = requiredViews
        self.capturedViews = capturedViews
        self.fraction = fraction
    }
}

public struct CaptureCalibration: Codable, Equatable, Sendable {
    public let method: String

    public init(method: String) {
        self.method = method
    }
}

public struct CaptureMetadata: Codable, Equatable, Sendable {
    public let method: String
    public let coverage: CaptureCoverage
    public let calibration: CaptureCalibration
    public let confidence: Double

    public init(
        method: String,
        coverage: CaptureCoverage,
        calibration: CaptureCalibration,
        confidence: Double
    ) {
        self.method = method
        self.coverage = coverage
        self.calibration = calibration
        self.confidence = confidence
    }
}

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .boolean(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct HandProfile: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let profileId: String
    public let createdAt: String
    public let handedness: Handedness
    public let units: MeasurementUnits
    public let coordinateSystem: String
    public let measurements: HandMeasurements
    public let landmarks: [String: LandmarkMeasurement]
    public let capture: CaptureMetadata
    public let extensions: [String: JSONValue]

    public init(
        schemaVersion: String = "1.0.0",
        profileId: String,
        createdAt: String,
        handedness: Handedness,
        units: MeasurementUnits = .millimeters,
        coordinateSystem: String = "gripit-hand-v1",
        measurements: HandMeasurements,
        landmarks: [String: LandmarkMeasurement],
        capture: CaptureMetadata,
        extensions: [String: JSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.profileId = profileId
        self.createdAt = createdAt
        self.handedness = handedness
        self.units = units
        self.coordinateSystem = coordinateSystem
        self.measurements = measurements
        self.landmarks = landmarks
        self.capture = capture
        self.extensions = extensions
    }
}

public enum HandProfileCodingError: Error, Equatable, Sendable {
    case malformedSchemaVersion(String)
    case unsupportedMajorVersion(Int)
}

public enum HandProfileCodec {
    public static func decode(_ data: Data) throws -> HandProfile {
        let envelope = try JSONDecoder().decode(SchemaEnvelope.self, from: data)
        let major = envelope.schemaVersion.split(separator: ".").first.flatMap { Int($0) }
        guard let major else {
            throw HandProfileCodingError.malformedSchemaVersion(envelope.schemaVersion)
        }
        guard major == 1 else {
            throw HandProfileCodingError.unsupportedMajorVersion(major)
        }
        return try JSONDecoder().decode(HandProfile.self, from: data)
    }

    public static func encode(_ profile: HandProfile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(profile)
    }

    private struct SchemaEnvelope: Decodable {
        let schemaVersion: String
    }
}
