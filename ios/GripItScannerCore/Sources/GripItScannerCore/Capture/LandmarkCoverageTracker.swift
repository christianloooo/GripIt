public struct LandmarkCoverageSnapshot: Equatable, Sendable {
    public let minimumSamplesPerLandmark: Int
    public let counts: [HandLandmarkName: Int]
    public let countsByView: [ScanView: [HandLandmarkName: Int]]

    public func fraction(for landmark: HandLandmarkName) -> Double {
        fraction(for: counts[landmark, default: 0])
    }

    public func fraction(for landmark: HandLandmarkName, in view: ScanView) -> Double {
        fraction(for: countsByView[view]?[landmark] ?? 0)
    }

    private func fraction(for count: Int) -> Double {
        min(1, Double(count) / Double(minimumSamplesPerLandmark))
    }
}

public struct LandmarkCoverageTracker: Sendable {
    public let minimumSamplesPerLandmark: Int

    private var counts: [HandLandmarkName: Int] = [:]
    private var countsByView: [ScanView: [HandLandmarkName: Int]] = [:]

    public init(minimumSamplesPerLandmark: Int = 3) {
        self.minimumSamplesPerLandmark = max(1, minimumSamplesPerLandmark)
    }

    public mutating func record(validLandmarks: Set<HandLandmarkName>, view: ScanView) {
        for landmark in validLandmarks {
            counts[landmark, default: 0] += 1
            countsByView[view, default: [:]][landmark, default: 0] += 1
        }
    }

    public var snapshot: LandmarkCoverageSnapshot {
        LandmarkCoverageSnapshot(
            minimumSamplesPerLandmark: minimumSamplesPerLandmark,
            counts: counts,
            countsByView: countsByView
        )
    }
}
