import Foundation

public enum HandIdentityDecision: Equatable, Sendable {
    case showPalm
    case wrongHand
    case confirmingPalm
    case tracked(identityConfidence: Double)
}

/// Hand-label confidence establishes identity, not per-frame measurement quality.
/// This is a spatial continuity heuristic, not biometric hand identification.
public struct HandIdentityTracker: Sendable {
    public let hand: Handedness
    public private(set) var identityConfidence: Double?
    private var candidateScores: [Double] = []
    private var lastAnchor: PixelPoint?
    private var lastScale: Double?
    private var lastTimestamp: Double?

    public init(hand: Handedness) { self.hand = hand }

    public mutating func reset() {
        identityConfidence = nil
        candidateScores = []
        lastAnchor = nil
        lastScale = nil
        lastTimestamp = nil
    }

    public mutating func noteMissing(timestamp: Double) {
        candidateScores = []
        if !timestamp.isFinite || lastTimestamp.map({ timestamp - $0 > 0.75 || timestamp < $0 }) == true {
            reset()
        }
    }

    public mutating func update(
        detectedHand: Handedness?, labelConfidence: Double, observedView: ScanView?,
        sensorPoints: [PixelPoint], timestamp: Double, palmFacing: Double? = nil
    ) -> HandIdentityDecision {
        guard timestamp.isFinite, labelConfidence.isFinite, (0...1).contains(labelConfidence),
              palmFacing.map(\.isFinite) != false,
              sensorPoints.count == 21,
              sensorPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) })
        else { reset(); return .showPalm }
        let anchor = sensorPoints[0]
        let scale = hypot(sensorPoints[9].x - anchor.x, sensorPoints[9].y - anchor.y)
        guard scale >= 0.015 else { reset(); return .showPalm }
        if let lastTimestamp, timestamp <= lastTimestamp || timestamp - lastTimestamp > 0.75 { reset() }
        if let lastAnchor, let lastScale {
            let displacement = hypot(anchor.x - lastAnchor.x, anchor.y - lastAnchor.y)
            if displacement > max(0.12, lastScale * 0.75) || !(0.5...2).contains(scale / lastScale) { reset() }
        }
        lastAnchor = anchor
        lastScale = scale
        lastTimestamp = timestamp

        if let identityConfidence {
            // Only a near-frontal palm or back carries a trustworthy left/right
            // label. Side angles routinely read as the other hand.
            let frontal = palmFacing.map { abs($0) > 0.90 }
                ?? (observedView == .palm || observedView == .back)
            if frontal, labelConfidence >= 0.9, let detectedHand, detectedHand != hand {
                reset()
                return .wrongHand
            }
            return .tracked(identityConfidence: identityConfidence)
        }
        guard labelConfidence >= 0.8 else { candidateScores = []; return .showPalm }
        guard detectedHand == hand else { candidateScores = []; return .wrongHand }
        guard observedView == .palm else { candidateScores = []; return .showPalm }
        candidateScores.append(labelConfidence)
        guard candidateScores.count >= 3 else { return .confirmingPalm }
        let confidence = candidateScores.min()!
        identityConfidence = confidence
        candidateScores = []
        return .tracked(identityConfidence: confidence)
    }
}
