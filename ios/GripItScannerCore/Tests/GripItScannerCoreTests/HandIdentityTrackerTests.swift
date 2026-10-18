import XCTest
@testable import GripItScannerCore

final class HandIdentityTrackerTests: XCTestCase {
    private let points = (0..<21).map { index in
        PixelPoint(x: 0.4 + Double(index % 4) * 0.03, y: 0.8 - Double(index) * 0.02)
    }

    func testAmbiguousSideLabelsDoNotRejectContinuousLockedHand() {
        var tracker = HandIdentityTracker(hand: .right)
        for index in 0..<3 {
            _ = tracker.update(detectedHand: .right, labelConfidence: 0.95, observedView: .palm,
                               sensorPoints: points, timestamp: Double(index) * 0.125)
        }
        XCTAssertEqual(tracker.update(detectedHand: .left, labelConfidence: 0.55,
                                      observedView: .thumbSide, sensorPoints: points, timestamp: 0.375),
                       .tracked(identityConfidence: 0.95))
    }

    func testWrongHandAndSideViewCannotEstablishIdentity() {
        var tracker = HandIdentityTracker(hand: .right)
        XCTAssertEqual(tracker.update(detectedHand: .left, labelConfidence: 0.95,
                                      observedView: .palm, sensorPoints: points, timestamp: 1), .wrongHand)
        XCTAssertEqual(tracker.update(detectedHand: .right, labelConfidence: 0.95,
                                      observedView: .thumbSide, sensorPoints: points, timestamp: 1.125), .showPalm)
    }

    func testLossAndAbruptJumpRequirePalmReacquisition() {
        var tracker = HandIdentityTracker(hand: .right)
        for index in 0..<3 {
            _ = tracker.update(detectedHand: .right, labelConfidence: 0.95, observedView: .palm,
                               sensorPoints: points, timestamp: Double(index) * 0.125)
        }
        XCTAssertEqual(tracker.update(detectedHand: .right, labelConfidence: 0.95,
                                      observedView: .thumbSide, sensorPoints: points, timestamp: 2), .showPalm)
        for index in 0..<3 {
            _ = tracker.update(detectedHand: .right, labelConfidence: 0.95, observedView: .palm,
                               sensorPoints: points, timestamp: 3 + Double(index) * 0.125)
        }
        let moved = points.map { PixelPoint(x: $0.x + 0.3, y: $0.y) }
        XCTAssertEqual(tracker.update(detectedHand: .right, labelConfidence: 0.95,
                                      observedView: .thumbSide, sensorPoints: moved, timestamp: 3.375), .showPalm)
    }

    func testExplicitLossCannotKeepAnOldIdentity() {
        var tracker = HandIdentityTracker(hand: .right)
        for index in 0..<3 {
            _ = tracker.update(detectedHand: .right, labelConfidence: 0.95, observedView: .palm,
                               sensorPoints: points, timestamp: Double(index) * 0.125)
        }
        tracker.reset()
        XCTAssertEqual(tracker.update(detectedHand: .right, labelConfidence: 0.55,
                                      observedView: .thumbSide, sensorPoints: points, timestamp: 0.375), .showPalm)
    }

    func testBriefMissingFrameKeepsTrackButLongLossInvalidatesIt() {
        var tracker = HandIdentityTracker(hand: .right)
        for index in 0..<3 {
            _ = tracker.update(detectedHand: .right, labelConfidence: 0.95, observedView: .palm,
                               sensorPoints: points, timestamp: Double(index) * 0.125)
        }
        tracker.noteMissing(timestamp: 0.375)
        XCTAssertEqual(tracker.update(detectedHand: .left, labelConfidence: 0.55,
                                      observedView: .thumbSide, sensorPoints: points, timestamp: 0.5),
                       .tracked(identityConfidence: 0.95))
        tracker.noteMissing(timestamp: 2)
        XCTAssertNil(tracker.identityConfidence)
    }

    func testReliableOppositeFrontalHandInvalidatesLockButObliqueLabelDoesNot() {
        var tracker = HandIdentityTracker(hand: .right)
        for index in 0..<3 {
            _ = tracker.update(detectedHand: .right, labelConfidence: 0.95, observedView: .palm,
                               sensorPoints: points, timestamp: Double(index) * 0.125)
        }
        XCTAssertEqual(tracker.update(detectedHand: .left, labelConfidence: 0.99, observedView: .palm,
                                      sensorPoints: points, timestamp: 0.375, palmNormalZ: -0.866),
                       .tracked(identityConfidence: 0.95), "A three-quarter side can overlap the palm classifier")
        XCTAssertEqual(tracker.update(detectedHand: .left, labelConfidence: 0.99, observedView: .back,
                                      sensorPoints: points, timestamp: 0.5, palmNormalZ: 1), .wrongHand)
        XCTAssertNil(tracker.identityConfidence)
    }

    func testInvalidInputAndScaleJumpCannotReuseLockedIdentity() {
        for invalidPoints in [Array(points.prefix(20)), points.map { PixelPoint(x: .nan, y: $0.y) },
                              points.map { PixelPoint(x: $0.x, y: 0.8 + ($0.y - 0.8) * 0.4) }] {
            var tracker = HandIdentityTracker(hand: .right)
            for index in 0..<3 {
                _ = tracker.update(detectedHand: .right, labelConfidence: 0.95, observedView: .palm,
                                   sensorPoints: points, timestamp: Double(index) * 0.125)
            }
            XCTAssertEqual(tracker.update(detectedHand: .right, labelConfidence: 0.55,
                                          observedView: .thumbSide, sensorPoints: invalidPoints, timestamp: 0.375), .showPalm)
        }
    }

    func testFourViewsCompleteWithAmbiguousSideLabelsAndStrictMetricGates() throws {
        for hand in [Handedness.right, .left] {
            var identity = HandIdentityTracker(hand: hand)
            var session = ScannerSession(minimumFramesPerView: 8, minimumConfidence: 0.8)
            var stability = MeasurementStabilityGate()
            var depthHistory = RecentDepthLandmarks()
            var timestamp = 0.0
            let palmZ = hand == .right ? -1.0 : 1.0
            let normals: [(Double, Double)] = [(0, palmZ), (-0.5, palmZ * 0.866), (0, -palmZ), (0.5, -palmZ * 0.866)]
            for (index, view) in ScanView.requiredOrder.enumerated() {
                stability.reset()
                depthHistory.reset()
                XCTAssertTrue(ScannerAdapterGeometry.matchesView(
                    normalX: normals[index].0, normalZ: normals[index].1, handedness: hand, requested: view))
                for frame in 0..<20 where session.coverage.snapshot.currentView == view {
                    timestamp += 0.125
                    let rawScore = view == .palm ? 0.95 : 0.55
                    let decision = identity.update(detectedHand: hand, labelConfidence: rawScore,
                                                   observedView: view, sensorPoints: points, timestamp: timestamp)
                    guard case .tracked(let identityScore) = decision else { continue }
                    let raw = fixtureObservation(view: view, handedness: hand, confidence: identityScore).landmarks
                    // Alternate real short-lived holes, as seen in the phone test.
                    var partial = raw
                    if frame.isMultiple(of: 2) { partial.removeValue(forKey: .indexTip) }
                    else { partial.removeValue(forKey: .pinkyTip) }
                    let measured = depthHistory.record(partial, view: view, timestamp: timestamp)
                    guard measured.count == 21, stability.accept(measured) else { continue }
                    try session.accept(ScanObservation(view: view, handedness: hand, landmarks: measured,
                                                       frameConfidence: identityScore))
                }
                XCTAssertTrue(session.coverage.snapshot.capturedViews.contains(view), "Stalled at \(view)")
            }
            XCTAssertTrue(session.coverage.snapshot.isComplete)
            let profile = try session.makeProfile(profileId: "continuous-track", createdAt: "2026-10-17")
            XCTAssertEqual(profile.capture.coverage.fraction, 1)
            XCTAssertEqual(profile.capture.confidence, 0.95)
        }
    }
}
