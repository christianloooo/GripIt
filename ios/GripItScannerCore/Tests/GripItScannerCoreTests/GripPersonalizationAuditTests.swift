import XCTest
import simd

@testable import GripItScannerCore

final class GripPersonalizationAuditTests: XCTestCase {
  private func profile(_ measurements: HandMeasurements) throws -> HandProfile {
    let sample = try SampleHandProfiles.averageRight()
    // Same ID deliberately: geometry must depend on measurements, not identity.
    return HandProfile(profileId: "audit", createdAt: sample.createdAt, handedness: .right,
      measurements: measurements, landmarks: [:], capture: sample.capture)
  }

  func testIndependentLengthAndDiameterChangeActualSkin() throws {
    let hand = try GripHandAsset.load()
    let sample = try SampleHandProfiles.averageRight()
    let fit = try GripPoseSolver.initialFit(profile: sample, pitch: .fourSeam, hand: hand)
    let index = try XCTUnwrap(fit.fingers.first { $0.finger == .index })
    let f = sample.measurements.fingers
    func measurements(lengthScale: Double, widthScale: Double) -> HandMeasurements {
      HandMeasurements(palm: sample.measurements.palm, fingers: FingerMeasurementSet(
        index: FingerMeasurements(segmentsMm: index.lengths.map { $0 * lengthScale },
          diameterMm: index.radius * 2 * widthScale),
        middle: f.middle, ring: f.ring, pinky: f.pinky, thumb: f.thumb))
    }
    let baseline = try GripPoseSolver.openHand(profile: profile(measurements(lengthScale: 1, widthScale: 1)))
    let longer = try GripPoseSolver.openHand(profile: profile(measurements(lengthScale: 1.08, widthScale: 1)))
    let wider = try GripPoseSolver.openHand(profile: profile(measurements(lengthScale: 1, widthScale: 1.08)))
    let a = try XCTUnwrap(baseline.fingers.first { $0.finger == .index })
    let b = try XCTUnwrap(longer.fingers.first { $0.finger == .index })
    let c = try XCTUnwrap(wider.fingers.first { $0.finger == .index })
    let lengthRatio = b.lengths.reduce(0, +) / a.lengths.reduce(0, +)
    XCTAssertGreaterThan(lengthRatio, 1.04)
    XCTAssertLessThan(lengthRatio, 1.08,
      "The existing anatomy bound clips this request; do not mistake effective length for raw scan length")
    XCTAssertTrue(longer.diagnostics.adjustedProportions)
    XCTAssertEqual(c.radius / a.radius, 1.08, accuracy: 0.00001)
    XCTAssertEqual(c.lengths, a.lengths)
    XCTAssertEqual(b.radius, a.radius)
    let ids = GripPoseSolver.padIndices(hand: hand, finger: .index)
    func displacement(_ pose: GripPose) -> Double {
      ids.map { simd_distance(pose.vertices[$0], baseline.vertices[$0]) }.max()!
    }
    XCTAssertGreaterThan(displacement(longer), 2)
    XCTAssertGreaterThan(displacement(wider), 0.2)
    print("AUDIT index: length \(a.lengths.reduce(0,+)) -> \(b.lengths.reduce(0,+)) mm; diameter \(a.radius*2) -> \(c.radius*2) mm; skin movement length=\(displacement(longer)), width=\(displacement(wider)) mm")
  }

  func testDepthObservationsChangeEveryPitchMeshButDoNotMeasureWidth() throws {
    let aggregator = HandMeasurementAggregator()
    let small = try aggregator.measure([fixtureObservation(view: .palm, scale: 1)])
    let large = try aggregator.measure([fixtureObservation(view: .palm, scale: 1.1)])
    XCTAssertNil(small.palm.thicknessMm)
    XCTAssertNil(small.fingers.index.diameterMm)
    XCTAssertEqual(large.fingers.index.segmentsMm[0] / small.fingers.index.segmentsMm[0], 1.1, accuracy: 0.00001)
    for pitch in PitchGrip.allCases {
      let a = try GripPoseSolver.solve(profile: profile(small), pitch: pitch)
      let b = try GripPoseSolver.solve(profile: profile(large), pitch: pitch)
      let movement = zip(a.vertices, b.vertices).map { simd_distance($0, $1) }.max()!
      XCTAssertGreaterThan(movement, 3, "\(pitch): scan dimensions must change the rendered skin")
      for finger in GripFinger.allCases {
        let x = try XCTUnwrap(a.fingers.first { $0.finger == finger })
        let y = try XCTUnwrap(b.fingers.first { $0.finger == finger })
        XCTAssertEqual(y.lengths.reduce(0,+) / x.lengths.reduce(0,+), 1.1, accuracy: 0.00001)
      }
      XCTAssertEqual(GripPoseSolver.ballRadius, 36.5, "The hand changes; baseball size stays fixed")
      print("AUDIT \(pitch.rawValue): +10% observed hand dimensions move skin up to \(movement) mm")
    }
  }
}
