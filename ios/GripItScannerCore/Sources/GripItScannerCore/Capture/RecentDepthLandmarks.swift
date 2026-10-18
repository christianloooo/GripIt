import Foundation

/// Bridges short depth holes using real measurements from the same steady pose.
/// Never predicts hidden joints. Samples expire after 350 ms and reset on motion,
/// view changes, tracking loss, invalid coordinates, or nonmonotonic timestamps.
public struct RecentDepthLandmarks: Sendable {
    private var samples: [HandLandmarkName: (landmark: NamedLandmark, time: Double)] = [:]
    private var view: ScanView?
    private var lastTimestamp: Double?
    public init() {}

    public mutating func reset() {
        samples = [:]
        view = nil
        lastTimestamp = nil
    }

    public mutating func record(
        _ landmarks: [HandLandmarkName: NamedLandmark], view: ScanView, timestamp: Double
    ) -> [HandLandmarkName: NamedLandmark] {
        guard timestamp.isFinite, landmarks.count >= 18,
              landmarks.allSatisfy({ name, landmark in
                  name == landmark.name && landmark.confidence.isFinite && landmark.confidence >= 0.8
                    && [landmark.point.xMm, landmark.point.yMm, landmark.point.zMm].allSatisfy(\.isFinite)
              }) else { reset(); return [:] }
        if self.view != view || lastTimestamp.map({ timestamp <= $0 }) == true { reset() }
        samples = samples.filter { timestamp - $0.value.time <= 0.35 }
        let motion = landmarks.compactMap { name, point -> Double? in
            samples[name].map { point.point.distance(to: $0.landmark.point) }
        }
        if !samples.isEmpty {
            let rms = motion.isEmpty ? .infinity
                : sqrt(motion.reduce(0) { $0 + $1 * $1 } / Double(motion.count))
            if motion.count < 15 || rms > 6 { samples = [:] }
        }
        self.view = view
        lastTimestamp = timestamp
        for (name, landmark) in landmarks { samples[name] = (landmark, timestamp) }
        return samples.mapValues(\.landmark)
    }
}
