import XCTest
import simd

@testable import GripItScannerCore

final class GripPoseTests: XCTestCase {
  func testGuidePosesPreserveMeasuredBonesAndConnectedMesh() throws {
    let profile = try SampleHandProfiles.averageRight()
    let hand = try GripHandAsset.load()
    let ball = try GripBallAsset.load()
    for pitch in PitchGrip.allCases {
      let pose = try GripPoseSolver.solve(profile: profile, pitch: pitch, hand: hand, ball: ball)
      for finger in pose.fingers {
        let distal = hand.joints.firstIndex { $0.name == finger.finger.jointNames[2] }!
        let tip = hand.joints.firstIndex { $0.name == finger.finger.jointNames[3] }!
        let direction = simd_normalize(finger.points[3] - finger.points[2])
        let cap = hand.vertices.indices.filter {
          hand.weights[$0][distal] + hand.weights[$0][tip] > 0.6
        }
        .map { simd_dot(pose.vertices[$0] - finger.points[2], direction) }.max()!
        XCTAssertEqual(
          cap, finger.lengths[2], accuracy: 1,
          "Rendered skin must end at the measured fingertip, not beyond an interior XR tip marker")
        for j in 0..<3 {
          XCTAssertEqual(
            simd_distance(finger.points[j], finger.points[j + 1]), finger.lengths[j],
            accuracy: 0.00001)
        }
      }
      for rig in pose.fingers where rig.contact && !(pitch == .circleChange && rig.finger == .thumb)
      {
        let gap = GripPoseSolver.padVertices(
          hand: hand, vertices: pose.vertices, finger: rig.finger
        ).map { abs(simd_distance($0, pose.ballCenter) - 36.5) }.min()!
        XCTAssertLessThan(
          gap, 3,
          "The rendered pad should touch the baseball, not float at a matching bone coordinate")
      }
      let thumb = try XCTUnwrap(pose.fingers.first { $0.finger == .thumb })
      XCTAssertGreaterThan(
        thumb.points[1].y, thumb.points[0].y,
        "The thumb metacarpal must extend away from the wrist instead of folding into it")
      XCTAssertLessThan(
        pose.diagnostics.maximumContactGapMm, 6,
        "\(pitch): "
          + pose.fingers.filter { $0.contact }.map {
            "\($0.finger): gap=\($0.targetError), angles=\($0.angles), yaw=\($0.yaw)"
          }.joined(separator: "; "))
      XCTAssertLessThan(pose.diagnostics.maximumSkinPenetrationMm, 3)
      XCTAssertLessThan(pose.diagnostics.maximumEdgeStretch, 6)
      if let gap = pose.diagnostics.loopGapMm {
        XCTAssertLessThan(gap, 4)
      }
      for finger in pose.fingers where pitch.upperContacts.contains(finger.finger) {
        let normal = simd_normalize(finger.points[3] - pose.ballCenter)
        let local = pose.ballRotation.inverse.act(normal * 36.5)
        let seam = ball.seams.min {
          simd_distance(gv($0.position), local) < simd_distance(gv($1.position), local)
        }!
        let direction = simd_normalize(finger.points[3] - finger.points[2])
        let tangent = simd_normalize(direction - normal * simd_dot(normal, direction))
        let alignment = abs(simd_dot(tangent, pose.ballRotation.act(gv(seam.tangent))))
        let distance = simd_distance(gv(seam.position), local)
        if pitch == .slider && finger.finger == .index {
          XCTAssertGreaterThan(distance, 3, "Slider index pad should rest on leather")
        } else {
          XCTAssertLessThan(distance, 3, "Primary pad should meet the rendered stitching")
          if pitch == .fourSeam {
            XCTAssertLessThan(alignment, 0.5, "Four-seam pads cross the seams")
          } else {
            XCTAssertGreaterThan(
              alignment, 0.75, "Two-seam, slider middle and circle-change pads follow the seams")
          }
        }
      }
      XCTAssertEqual(pose.vertices.count, hand.vertices.count)
      XCTAssertGreaterThan(pose.vertices.count, 10000)
      XCTAssertTrue(pose.vertices.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
    }
  }
  func testScannedJointPositionsAndSegmentLengthsActuallyDriveThePose() throws {
    let sample = try SampleHandProfiles.averageRight()
    let landmarks = ["indexMCP": LandmarkMeasurement(xMm: 30, yMm: 77, zMm: 4, confidence: 0.95)]
    let measured = HandProfile(
      profileId: "measured-fixture", createdAt: sample.createdAt, handedness: .right,
      measurements: sample.measurements, landmarks: landmarks, capture: sample.capture)
    let pose = try GripPoseSolver.solve(profile: measured, pitch: .fourSeam)
    let root = try XCTUnwrap(pose.fingers.first { $0.finger == .index }).points[0]
    XCTAssertEqual(root, SIMD3(30, 77, 4))
    XCTAssertTrue(pose.diagnostics.usedMeasuredRoots)
    XCTAssertTrue(pose.diagnostics.modeledThickness)
  }
  func testLeftHandUsesTheSameCanonicalPoseAndOnlyTheRendererMirrors() throws {
    let sample = try SampleHandProfiles.averageRight()
    let left = HandProfile(
      profileId: "left-fixture", createdAt: sample.createdAt, handedness: .left,
      measurements: sample.measurements, landmarks: sample.landmarks, capture: sample.capture)
    let rightPose = try GripPoseSolver.solve(profile: sample, pitch: .twoSeam)
    let leftPose = try GripPoseSolver.solve(profile: left, pitch: .twoSeam)
    XCTAssertEqual(leftPose.vertices, rightPose.vertices)
    XCTAssertEqual(leftPose.handedness, .left)
  }
  func testInvalidMeasurementsAreRejectedInsteadOfGeneratingWarpedSkin() throws {
    let sample = try SampleHandProfiles.averageRight()
    let invalid = HandMeasurements(
      palm: sample.measurements.palm,
      fingers: FingerMeasurementSet(
        index: sample.measurements.fingers.index, middle: sample.measurements.fingers.middle,
        ring: sample.measurements.fingers.ring, pinky: sample.measurements.fingers.pinky,
        thumb: FingerMeasurements(segmentsMm: [30, 0, 20], diameterMm: nil)))
    let profile = HandProfile(
      profileId: "invalid", createdAt: sample.createdAt, handedness: .right, measurements: invalid,
      landmarks: [:], capture: sample.capture)
    XCTAssertThrowsError(try GripPoseSolver.solve(profile: profile, pitch: .fourSeam))
  }
  func testDifferentHandSizesPreserveTheirOwnBoneLengths() throws {
    let sample = try SampleHandProfiles.averageRight()
    for scale in [0.85, 1.15] {
      func finger(_ f: FingerMeasurements) -> FingerMeasurements {
        FingerMeasurements(segmentsMm: f.segmentsMm.map { $0 * scale }, diameterMm: nil)
      }
      let f = sample.measurements.fingers
      let m = HandMeasurements(
        palm: PalmMeasurements(
          widthMm: sample.measurements.palm.widthMm! * scale,
          lengthMm: sample.measurements.palm.lengthMm! * scale, thicknessMm: nil),
        fingers: FingerMeasurementSet(
          index: finger(f.index), middle: finger(f.middle), ring: finger(f.ring),
          pinky: finger(f.pinky), thumb: finger(f.thumb)))
      let p = HandProfile(
        profileId: "scaled", createdAt: sample.createdAt, handedness: .right, measurements: m,
        landmarks: [:], capture: sample.capture)
      for pitch in PitchGrip.allCases {
        let pose = try GripPoseSolver.solve(profile: p, pitch: pitch)
        XCTAssertLessThan(pose.diagnostics.maximumSkinPenetrationMm, 6)
        let plan = GripPlan(pose: pose)
        for zone in plan.zones where zone.zoneId != .wrist {
          XCTAssertNotNil(zone.shortfallMm)
          XCTAssertTrue(zone.shortfallMm?.isFinite == true)
        }
        for rig in pose.fingers {
          for j in 0..<3 {
            XCTAssertEqual(
              simd_distance(rig.points[j], rig.points[j + 1]), rig.lengths[j], accuracy: 0.00001)
          }
        }
      }
    }
  }

  func testNeutralHandHasMeasuredBonesAndAnchoredPalmAcrossGrips() throws {
    let profile = try SampleHandProfiles.averageRight()
    let hand = try GripHandAsset.load()
    let open = try GripPoseSolver.openHand(profile: profile)
    for finger in open.fingers {
      XCTAssertEqual(finger.points.count, 4)
      for segment in 0..<3 {
        XCTAssertEqual(
          simd_distance(finger.points[segment], finger.points[segment + 1]),
          finger.lengths[segment], accuracy: 0.00001)
      }
    }
    let wrist = hand.joints.firstIndex { $0.name == "wrist" }!
    let anchors = hand.vertices.indices.filter { hand.weights[$0][wrist] > 0.995 }
    XCTAssertGreaterThan(anchors.count, 100)
    for pitch in PitchGrip.allCases {
      let posed = try GripPoseSolver.solve(profile: profile, pitch: pitch)
      for i in anchors {
        XCTAssertLessThan(
          simd_distance(open.vertices[i], posed.vertices[i]), 0.8,
          "Bending fingers must not pull the anchored palm/wrist into a web")
      }
    }
  }

  func testReviewFlexionPreservesLengthsAndWristWhileShowingRealJointBends() throws {
    let profile = try SampleHandProfiles.averageRight()
    let open = try GripPoseSolver.openHand(profile: profile)
    let bent = try GripPoseSolver.openHand(profile: profile, flexion: 0.6)
    XCTAssertNotEqual(open.vertices, bent.vertices)
    for finger in bent.fingers {
      for j in 0..<3 {
        XCTAssertEqual(
          simd_distance(finger.points[j], finger.points[j + 1]), finger.lengths[j],
          accuracy: 0.00001)
      }
    }
    let hand = try GripHandAsset.load()
    let wrist = hand.joints.firstIndex { $0.name == "wrist" }!
    for i in hand.vertices.indices where hand.weights[i][wrist] > 0.995 {
      XCTAssertLessThan(simd_distance(open.vertices[i], bent.vertices[i]), 0.8)
    }
    XCTAssertThrowsError(try GripPoseSolver.openHand(profile: profile, flexion: .nan))
    XCTAssertThrowsError(try GripPoseSolver.openHand(profile: profile, flexion: 1))
  }

  func testClearPinkyDoesNotCloseIntoAnUnintendedCircle() throws {
    let profile = try SampleHandProfiles.averageRight()
    for pitch in [PitchGrip.fourSeam, .twoSeam, .slider] {
      let pose = try GripPoseSolver.solve(profile: profile, pitch: pitch)
      let pinky = try XCTUnwrap(pose.fingers.first { $0.finger == .pinky })
      XCTAssertGreaterThan(pinky.points[3].y - pinky.points[0].y, 20)
      XCTAssertGreaterThan(
        simd_distance(pinky.points[3], pinky.points[0]), pinky.lengths.reduce(0, +) * 0.55)
      XCTAssertLessThan(pinky.angles.reduce(0, +), Double.pi)
    }
  }

  func testReferenceHandHasSlimPalmAndNaturalDigitSpacing() throws {
    let profile = try SampleHandProfiles.averageRight()
    let hand = try GripHandAsset.load()
    let pose = try GripPoseSolver.openHand(profile: profile)
    let core = hand.vertices.indices.filter {
      abs(hand.vertices[$0][0]) < 10 && (30...50).contains(hand.vertices[$0][1])
    }
    let depths = core.map { pose.vertices[$0].z }
    let thickness = depths.max()! - depths.min()!
    XCTAssertGreaterThan(thickness, 10)
    XCTAssertLessThan(thickness, 16, "The default palm must not swell into a thick block")
    let fingers = [GripFinger.index, .middle, .ring, .pinky].map { f in
      pose.fingers.first { $0.finger == f }!
    }
    for i in 0..<3 {
      let a = fingers[i]
      let b = fingers[i + 1]
      let rootGap = abs(a.points[0].x - b.points[0].x) - (a.radius + b.radius)
      XCTAssertGreaterThan(rootGap, 0)
      XCTAssertLessThan(rootGap, 12)
      XCTAssertLessThan(abs(a.points[3].x - b.points[3].x) - (a.radius + b.radius) * 0.75, 12)
    }
    let measured = HandProfile(
      profileId: "measured-depth", createdAt: profile.createdAt, handedness: .right,
      measurements: HandMeasurements(
        palm: PalmMeasurements(
          widthMm: profile.measurements.palm.widthMm,
          lengthMm: profile.measurements.palm.lengthMm, thicknessMm: 20),
        fingers: profile.measurements.fingers),
      landmarks: [:], capture: profile.capture)
    let actual = try GripPoseSolver.openHand(profile: measured)
    let measuredDepths = core.map { actual.vertices[$0].z }
    XCTAssertGreaterThan(
      measuredDepths.max()! - measuredDepths.min()!, thickness * 1.3,
      "Actual measured thickness must remain authoritative")
  }
  func testSuppliedCleanBallIsTheNormalizedSourceWithPBRTextures() throws {
    let ball = try GripBallAsset.load()
    XCTAssertEqual(ball.variant, "Baseball_Ball_Clean")
    XCTAssertEqual(
      ball.sourceSHA256, "29dffd40550f1a938d2caa63a2061a1c3b57e5e5e055637ba5bed30f49c0a0ca")
    XCTAssertEqual(ball.radiusMm, 36.5)
    XCTAssertNotNil(ball.normalTextureURL)
    XCTAssertNotNil(ball.materialTextureURL)
    XCTAssertEqual(ball.normals?.count, ball.vertices.count)
    for v in ball.vertices { XCTAssertEqual(simd_length(gv(v)), 36.5, accuracy: 0.0001) }
    XCTAssertGreaterThan(ball.seams.count, 500)
  }

}
