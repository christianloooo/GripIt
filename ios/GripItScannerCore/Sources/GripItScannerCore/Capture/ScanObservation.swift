public enum ScanView: String, Codable, CaseIterable, Equatable, Sendable {
    case palm
    case back
    case thumbSide = "thumb-side"
    case pinkySide = "pinky-side"

    public static let requiredOrder: [ScanView] = [.palm, .back, .thumbSide, .pinkySide]
}

public enum HandLandmarkName: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case wrist
    case thumbCMC
    case thumbMCP
    case thumbIP
    case thumbTip
    case indexMCP
    case indexPIP
    case indexDIP
    case indexTip
    case middleMCP
    case middlePIP
    case middleDIP
    case middleTip
    case ringMCP
    case ringPIP
    case ringDIP
    case ringTip
    case pinkyMCP
    case pinkyPIP
    case pinkyDIP
    case pinkyTip
}

public struct NamedLandmark: Equatable, Sendable {
    public let name: HandLandmarkName
    public let point: MetricPoint3D
    public let confidence: Double

    public init(name: HandLandmarkName, point: MetricPoint3D, confidence: Double) {
        self.name = name
        self.point = point
        self.confidence = confidence
    }
}

public enum CoordinateCanonicalizationError: Error, Equatable, Sendable {
    case missingLandmark(HandLandmarkName)
    case landmarkNameMismatch(key: HandLandmarkName, value: HandLandmarkName)
    case nonFiniteLandmark(HandLandmarkName)
    case degenerateHandBasis
}

public struct ScanObservation: Equatable, Sendable {
    public let view: ScanView
    public let handedness: Handedness
    public let landmarks: [HandLandmarkName: NamedLandmark]
    public let frameConfidence: Double

    public init(
        view: ScanView,
        handedness: Handedness,
        landmarks: [HandLandmarkName: NamedLandmark],
        frameConfidence: Double
    ) {
        self.view = view
        self.handedness = handedness
        self.landmarks = landmarks
        self.frameConfidence = frameConfidence
    }

    public func canonicalized() throws -> ScanObservation {
        for (key, landmark) in landmarks {
            guard key == landmark.name else {
                throw CoordinateCanonicalizationError.landmarkNameMismatch(
                    key: key,
                    value: landmark.name
                )
            }
            guard landmark.point.xMm.isFinite,
                  landmark.point.yMm.isFinite,
                  landmark.point.zMm.isFinite
            else {
                throw CoordinateCanonicalizationError.nonFiniteLandmark(key)
            }
        }

        func point(_ name: HandLandmarkName) throws -> Vector3 {
            guard let point = landmarks[name]?.point else {
                throw CoordinateCanonicalizationError.missingLandmark(name)
            }
            return Vector3(point)
        }

        let origin = try point(.wrist)
        let xAxis = try (point(.indexMCP) - point(.pinkyMCP)).normalized()
        let palmCenter = try [
            point(.indexMCP), point(.middleMCP), point(.ringMCP), point(.pinkyMCP),
        ].reduce(Vector3.zero, +) / 4
        let yCandidate = palmCenter - origin
        let yAxis = try (yCandidate - xAxis * yCandidate.dot(xAxis)).normalized()
        let derivedZAxis = try xAxis.cross(yAxis).normalized()
        let zAxis = handedness == .left ? derivedZAxis * -1 : derivedZAxis

        let canonicalLandmarks = landmarks.mapValues { landmark in
            let relative = Vector3(landmark.point) - origin
            return NamedLandmark(
                name: landmark.name,
                point: MetricPoint3D(
                    xMm: relative.dot(xAxis),
                    yMm: relative.dot(yAxis),
                    zMm: relative.dot(zAxis)
                ),
                confidence: landmark.confidence
            )
        }
        return ScanObservation(
            view: view,
            handedness: handedness,
            landmarks: canonicalLandmarks,
            frameConfidence: frameConfidence
        )
    }
}

private struct Vector3 {
    static let zero = Vector3(x: 0, y: 0, z: 0)

    let x: Double
    let y: Double
    let z: Double

    init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(_ point: MetricPoint3D) {
        self.init(x: point.xMm, y: point.yMm, z: point.zMm)
    }

    static func + (left: Vector3, right: Vector3) -> Vector3 {
        Vector3(x: left.x + right.x, y: left.y + right.y, z: left.z + right.z)
    }

    static func - (left: Vector3, right: Vector3) -> Vector3 {
        Vector3(x: left.x - right.x, y: left.y - right.y, z: left.z - right.z)
    }

    static func * (left: Vector3, right: Double) -> Vector3 {
        Vector3(x: left.x * right, y: left.y * right, z: left.z * right)
    }

    static func / (left: Vector3, right: Double) -> Vector3 {
        Vector3(x: left.x / right, y: left.y / right, z: left.z / right)
    }

    func dot(_ other: Vector3) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    func cross(_ other: Vector3) -> Vector3 {
        Vector3(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    func normalized() throws -> Vector3 {
        let length = (x * x + y * y + z * z).squareRoot()
        guard length.isFinite, length > 0.000_001 else {
            throw CoordinateCanonicalizationError.degenerateHandBasis
        }
        return self / length
    }
}
