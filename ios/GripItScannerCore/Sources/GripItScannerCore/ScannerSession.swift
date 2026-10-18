public enum ScannerSessionError: Error, Equatable, Sendable {
    case incompleteCoverage
    case noObservations
    case mixedHandedness(expected: Handedness, actual: Handedness)
}

public struct ScannerSession: Sendable {
    public private(set) var coverage: CoverageTracker

    private var handedness: Handedness?
    private var observations: [ScanObservation] = []

    public init(minimumFramesPerView: Int = 8, minimumConfidence: Double = 0.8) {
        coverage = CoverageTracker(
            minimumFramesPerView: minimumFramesPerView,
            minimumConfidence: minimumConfidence
        )
    }

    public mutating func accept(_ observation: ScanObservation) throws {
        if let handedness, handedness != observation.handedness {
            throw ScannerSessionError.mixedHandedness(
                expected: handedness,
                actual: observation.handedness
            )
        }

        let canonicalObservation = try observation.canonicalized()
        try coverage.accept(observation)
        handedness = observation.handedness
        observations.append(canonicalObservation)
    }

    public func makeProfile(profileId: String, createdAt: String) throws -> HandProfile {
        guard coverage.snapshot.isComplete else {
            throw ScannerSessionError.incompleteCoverage
        }
        guard let handedness, !observations.isEmpty else {
            throw ScannerSessionError.noObservations
        }

        let measurements = try HandMeasurementAggregator().measure(observations)
        let snapshot = coverage.snapshot
        return HandProfile(
            profileId: profileId,
            createdAt: createdAt,
            handedness: handedness,
            measurements: measurements,
            landmarks: aggregateLandmarks(),
            capture: CaptureMetadata(
                method: "true-depth-mediapipe",
                coverage: CaptureCoverage(
                    requiredViews: snapshot.requiredViews.map(\.rawValue),
                    capturedViews: snapshot.capturedViews.map(\.rawValue),
                    fraction: snapshot.fraction
                ),
                calibration: CaptureCalibration(method: "camera-intrinsics"),
                confidence: median(observations.map(\.frameConfidence))
            ),
            extensions: [
                "gripit.scanner": .object([
                    "observationCount": .number(Double(observations.count)),
                ]),
            ]
        )
    }

    private func aggregateLandmarks() -> [String: LandmarkMeasurement] {
        Dictionary(uniqueKeysWithValues: HandLandmarkName.allCases.compactMap { name in
            let samples = observations.compactMap { $0.landmarks[name] }
            guard !samples.isEmpty else { return nil }
            return (
                name.rawValue,
                LandmarkMeasurement(
                    xMm: median(samples.map(\.point.xMm)),
                    yMm: median(samples.map(\.point.yMm)),
                    zMm: median(samples.map(\.point.zMm)),
                    confidence: median(samples.map(\.confidence))
                )
            )
        })
    }
}
