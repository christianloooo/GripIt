import Foundation

public enum MeasurementStabilityStatus: Equatable, Sendable {
    case settling, incompleteDepth, overlappingFingers, noisyDepth, moving, ready
}

/// Requires repeated metric observations before treating a frame as steady.
public struct MeasurementStabilityGate: Sendable {
    public private(set) var status: MeasurementStabilityStatus = .settling
    /// Per-landmark motion between the last two frames, in millimetres. Nil until
    /// two frames have been compared. Reported so the scanner can show why a pose
    /// was rejected instead of only that it was.
    public private(set) var motionRms: Double?
    /// Largest frame-to-frame change in any bone length, in millimetres.
    public private(set) var worstBoneChangeMm: Double?
    /// Shortest measured bone, in millimetres. Collapses when fingers overlap.
    public private(set) var shortestBoneMm: Double?
    /// Steady comparisons accumulated so far, out of `requiredStableComparisons`.
    public private(set) var stableComparisons = 0
    public static let requiredStableComparisons = 2
    public static let motionLimitMm = 6.0
    public static let minimumBoneMm = 4.0

    private var previous: [HandLandmarkName: MetricPoint3D]?
    public init() {}

    public mutating func reset() {
        previous = nil
        stableComparisons = 0
        status = .settling
        motionRms = nil
        worstBoneChangeMm = nil
        shortestBoneMm = nil
    }

    public mutating func accept(_ landmarks: [HandLandmarkName: NamedLandmark]) -> Bool {
        guard landmarks.count == HandLandmarkName.allCases.count,
              landmarks.values.allSatisfy({ [$0.point.xMm, $0.point.yMm, $0.point.zMm].allSatisfy(\.isFinite) }) else {
            reset()
            status = .incompleteDepth
            return false
        }
        let points = landmarks.mapValues(\.point)
        defer { previous = points }
        guard let previous else { status = .settling; return false }
        let motion = points.map { name, point in
            point.distance(to: previous[name] ?? point)
        }
        let rms = sqrt(motion.reduce(0) { $0 + $1 * $1 } / Double(motion.count))
        motionRms = rms
        let bones: [[HandLandmarkName]] = [
            [.thumbCMC, .thumbMCP, .thumbIP, .thumbTip],
            [.indexMCP, .indexPIP, .indexDIP, .indexTip],
            [.middleMCP, .middlePIP, .middleDIP, .middleTip],
            [.ringMCP, .ringPIP, .ringDIP, .ringTip],
            [.pinkyMCP, .pinkyPIP, .pinkyDIP, .pinkyTip]
        ]
        // Measure every bone first so the reported numbers describe the whole
        // hand, then judge. A single bad segment otherwise hid the rest.
        var lengths: [(current: Double, previous: Double)] = []
        for chain in bones {
            for (a, b) in zip(chain, chain.dropFirst()) {
                guard let first = points[a], let second = points[b],
                      let oldFirst = previous[a], let oldSecond = previous[b] else { reset(); return false }
                lengths.append((first.distance(to: second), oldFirst.distance(to: oldSecond)))
            }
        }
        shortestBoneMm = lengths.map(\.current).min()
        worstBoneChangeMm = lengths.map { abs($0.current - $0.previous) }.max()
        guard lengths.allSatisfy({ $0.current >= Self.minimumBoneMm }) else {
            stableComparisons = 0
            status = .overlappingFingers
            return false
        }
        guard lengths.allSatisfy({ abs($0.current - $0.previous) <= max(3, $0.previous * 0.15) }) else {
            stableComparisons = 0
            status = .noisyDepth
            return false
        }
        guard rms <= Self.motionLimitMm else {
            stableComparisons = 0
            status = .moving
            return false
        }
        stableComparisons += 1
        let steady = stableComparisons >= Self.requiredStableComparisons
        status = steady ? .ready : .settling
        return steady
    }
}
