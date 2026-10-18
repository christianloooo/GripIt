import Foundation

/// Requires repeated metric observations before treating a frame as steady.
public struct MeasurementStabilityGate: Sendable {
    private var previous: [HandLandmarkName: MetricPoint3D]?
    private var stableComparisons = 0
    public init() {}

    public mutating func reset() {
        previous = nil
        stableComparisons = 0
    }

    public mutating func accept(_ landmarks: [HandLandmarkName: NamedLandmark]) -> Bool {
        guard landmarks.count == HandLandmarkName.allCases.count,
              landmarks.values.allSatisfy({ [$0.point.xMm, $0.point.yMm, $0.point.zMm].allSatisfy(\.isFinite) }) else {
            reset()
            return false
        }
        let points = landmarks.mapValues(\.point)
        defer { previous = points }
        guard let previous else { return false }
        let motion = points.map { name, point in
            point.distance(to: previous[name] ?? point)
        }
        let rms = sqrt(motion.reduce(0) { $0 + $1 * $1 } / Double(motion.count))
        let bones: [[HandLandmarkName]] = [
            [.thumbCMC, .thumbMCP, .thumbIP, .thumbTip],
            [.indexMCP, .indexPIP, .indexDIP, .indexTip],
            [.middleMCP, .middlePIP, .middleDIP, .middleTip],
            [.ringMCP, .ringPIP, .ringDIP, .ringTip],
            [.pinkyMCP, .pinkyPIP, .pinkyDIP, .pinkyTip]
        ]
        for chain in bones {
            for (a, b) in zip(chain, chain.dropFirst()) {
                guard let first = points[a], let second = points[b],
                      let oldFirst = previous[a], let oldSecond = previous[b] else { reset(); return false }
                let length = first.distance(to: second)
                let oldLength = oldFirst.distance(to: oldSecond)
                guard length >= 4, abs(length - oldLength) <= max(3, oldLength * 0.15) else {
                    stableComparisons = 0
                    return false
                }
            }
        }
        guard rms <= 6 else { stableComparisons = 0; return false }
        stableComparisons += 1
        return stableComparisons >= 2
    }
}
