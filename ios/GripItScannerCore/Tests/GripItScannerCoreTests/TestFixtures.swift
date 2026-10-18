@testable import GripItScannerCore

func fixtureObservation(
    view: ScanView,
    scale: Double = 1,
    handedness: Handedness = .right,
    confidence: Double = 0.95,
    offset: (Double, Double, Double) = (0, 0, 0)
) -> ScanObservation {
    let raw: [HandLandmarkName: (Double, Double, Double)] = [
        .wrist: (0, 0, 0),
        .thumbCMC: (25, 18, 2), .thumbMCP: (38, 34, 4), .thumbIP: (48, 48, 6), .thumbTip: (58, 60, 8),
        .indexMCP: (30, 58, 0), .indexPIP: (32, 94, 1), .indexDIP: (33, 118, 1), .indexTip: (34, 137, 1),
        .middleMCP: (10, 62, 0), .middlePIP: (10, 102, 1), .middleDIP: (10, 129, 1), .middleTip: (10, 150, 1),
        .ringMCP: (-12, 60, 0), .ringPIP: (-14, 97, 1), .ringDIP: (-15, 122, 1), .ringTip: (-16, 141, 1),
        .pinkyMCP: (-30, 54, 0), .pinkyPIP: (-34, 83, 1), .pinkyDIP: (-36, 102, 1), .pinkyTip: (-38, 118, 1),
    ]
    let landmarks = Dictionary(uniqueKeysWithValues: raw.map { name, value in
        let point = MetricPoint3D(
            xMm: value.0 * scale + offset.0,
            yMm: value.1 * scale + offset.1,
            zMm: value.2 * scale + offset.2
        )
        return (name, NamedLandmark(name: name, point: point, confidence: confidence))
    })
    return ScanObservation(
        view: view,
        handedness: handedness,
        landmarks: landmarks,
        frameConfidence: confidence
    )
}
