import XCTest
import simd

@testable import GripItScannerCore

final class GripPoseTests: XCTestCase {
  func testPressureWidensLoadedPadsWithoutMovingNailsOrBridgingFloatingFingers() throws {
    let profile = try SampleHandProfiles.averageRight()
    let hand = try GripHandAsset.load()
    let pose = try GripPoseSolver.solve(profile: profile, pitch: .fourSeam)
    let fit = try GripPoseSolver.initialFit(profile: profile, pitch: .fourSeam, hand: hand)
    let raw = try GripPoseSolver.deform(
      hand: hand, fingers: pose.fingers,
      scale: fit.scale, center: pose.ballCenter)
    let medium = GripPoseSolver.compressContacts(
      hand: hand, vertices: raw,
      fingers: pose.fingers, center: pose.ballCenter, pitch: .twoSeam)
    let middle = try XCTUnwrap(pose.fingers.first { $0.finger == .middle })
    let contact = GripPoseSolver.skinContact(
      hand: hand, vertices: raw,
      finger: .middle, center: pose.ballCenter)
    let normal = simd_normalize(contact - pose.ballCenter)
    let across = simd_normalize(simd_cross(middle.points[3] - middle.points[2], normal))
    let ids = Set(GripPoseSolver.padIndices(hand: hand, finger: .middle))
    func widening(_ vertices: [SIMD3<Double>]) -> Double {
      ids.reduce(0) { sum, i in
        sum + abs(simd_dot(vertices[i] - contact, across)) - abs(simd_dot(raw[i] - contact, across))
      }
    }
    XCTAssertGreaterThan(widening(pose.vertices), 0.5, "Loaded skin should spread laterally")
    XCTAssertGreaterThan(
      widening(pose.vertices), widening(medium) * 1.1,
      "Firm pressure should spread the same pad more than medium pressure")
    let loaded = Set(
      [GripFinger.index, .middle, .thumb].flatMap {
        GripPoseSolver.padIndices(hand: hand, finger: $0)
      })
    var changed = 0
    for i in raw.indices {
      let movement = simd_distance(raw[i], pose.vertices[i])
      XCTAssertLessThanOrEqual(movement, 1.200001)
      if movement > 0.001 { changed += 1 }
      if !loaded.contains(i) {
        XCTAssertEqual(raw[i], pose.vertices[i], "Nails and unloaded skin stay intact")
      }
    }
    XCTAssertGreaterThan(changed, 30)
    func contactCount(_ vertices: [SIMD3<Double>]) -> Int {
      ids.filter { abs(simd_distance(vertices[$0], pose.ballCenter) - 36.5) < 0.3 }.count
    }
    XCTAssertGreaterThan(contactCount(pose.vertices), contactCount(raw))
    let far = pose.ballCenter + SIMD3<Double>(0, 0, 300)
    XCTAssertEqual(
      GripPoseSolver.compressContacts(
        hand: hand, vertices: raw, fingers: pose.fingers,
        center: far, pitch: .fourSeam), raw, "Pressure cannot conceal a floating grip")
    let weights = GripPoseSolver.contactPressureWeights(hand: hand, pose: pose)
    XCTAssertGreaterThan(weights.max()!, 0.8)
    XCTAssertTrue(weights.enumerated().allSatisfy { loaded.contains($0.offset) || $0.element == 0 })
    for f in pose.fingers where f.finger == .ring || f.finger == .pinky {
      XCTAssertGreaterThan(f.angles.reduce(0, +), 3, "Support fingers must curl into the side")
      XCTAssertGreaterThan(f.angles[0], 0.5, "Curl should begin at the knuckle")
    }
  }
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
      for rig in pose.fingers
      where rig.contact && !(pitch == .circleChange && [.thumb, .index].contains(rig.finger)) {
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
      // A bone-end target is not the pad surface of an authored hand. Keep
      // target errors visible in diagnostics; validate real skin contact here.
      XCTAssertLessThan(pose.diagnostics.maximumPadSurfaceGapMm, 3)
      XCTAssertLessThan(
        pose.diagnostics.maximumContactGapMm, 1.2,
        "A small fingerprint patch must touch, not only one lucky surface vertex")
      XCTAssertLessThan(pose.diagnostics.maximumSkinPenetrationMm, 3)
      XCTAssertLessThan(pose.diagnostics.maximumEdgeStretch, 6)
      if let gap = pose.diagnostics.loopGapMm {
        XCTAssertLessThan(gap, 4)
      }
      for finger in pose.fingers where finger.finger != .thumb {
        XCTAssertLessThanOrEqual(abs(finger.opposition), 0.12)
        XCTAssertLessThanOrEqual(abs(finger.yaw), 0.4)
        XCTAssertLessThanOrEqual(finger.angles[2], finger.angles[1] * 0.85 + 0.120001)
        XCTAssertGreaterThanOrEqual(finger.angles[2], finger.angles[1] * 0.35 - 0.000001)
      }
      for finger in pose.fingers where pitch.upperContacts.contains(finger.finger) {
        let contact = GripPoseSolver.skinContact(
          hand: hand, vertices: pose.vertices, finger: finger.finger, center: pose.ballCenter)
        let normal = simd_normalize(contact - pose.ballCenter)
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
      for seam in pose.diagnostics.seams {
        XCTAssertFalse(
          seam.needsReview, "Specific seam patch must fit the actual pad: \(pitch) \(seam)")
      }
      for finger in pose.fingers where pitch.upperContacts.contains(finger.finger) {
        guard let anchor = GripSeamTemplate.anchor(pitch, finger.finger) else { continue }
        let contact = GripPoseSolver.skinContact(
          hand: hand, vertices: pose.vertices,
          finger: finger.finger, center: pose.ballCenter)
        let local = pose.ballRotation.inverse.act(simd_normalize(contact - pose.ballCenter) * 36.5)
        XCTAssertLessThan(
          simd_distance(local, anchor), 12,
          "The finger must stay on its assigned stitching region as the grip depth changes")
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
    let baseline = try GripPoseSolver.openHand(profile: sample)
    let pose = try GripPoseSolver.openHand(profile: measured)
    let root = try XCTUnwrap(pose.fingers.first { $0.finger == .index }).points[0]
    let original = try XCTUnwrap(baseline.fingers.first { $0.finger == .index }).points[0]
    XCTAssertNotEqual(root, original)
    XCTAssertLessThan(
      simd_distance(root, SIMD3(30, 77, 4)), simd_distance(original, SIMD3(30, 77, 4)))
    XCTAssertLessThanOrEqual(abs(root.x - original.x), 3)
    XCTAssertLessThanOrEqual(abs(root.y - original.y), 3)
    XCTAssertLessThanOrEqual(abs(root.z - original.z), 3)
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
    let moving = Set(GripFinger.allCases.flatMap(\.jointNames))
    let anchoredBones = hand.joints.indices.filter { !moving.contains(hand.joints[$0].name) }
    let anchors = hand.vertices.indices.filter { i in
      anchoredBones.reduce(0.0) { $0 + hand.weights[i][$1] } > 0.995
    }
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
    let moving = Set(GripFinger.allCases.flatMap(\.jointNames))
    let fixed = hand.joints.indices.filter { !moving.contains(hand.joints[$0].name) }
    let anchors = hand.vertices.indices.filter { i in
      fixed.reduce(0.0) { $0 + hand.weights[i][$1] } > 0.995
    }
    XCTAssertGreaterThan(anchors.count, 100)
    for i in anchors {
      XCTAssertLessThan(simd_distance(open.vertices[i], bent.vertices[i]), 0.8)
    }
    XCTAssertThrowsError(try GripPoseSolver.openHand(profile: profile, flexion: .nan))
    XCTAssertThrowsError(try GripPoseSolver.openHand(profile: profile, flexion: 1))
  }

  func testPinkyTucksBesidePalmWhileStayingClearOfBall() throws {
    let profile = try SampleHandProfiles.averageRight()
    for pitch in [PitchGrip.fourSeam, .twoSeam, .slider] {
      let pose = try GripPoseSolver.solve(profile: profile, pitch: pitch)
      let pinky = try XCTUnwrap(pose.fingers.first { $0.finger == .pinky })
      XCTAssertLessThan(
        pinky.points[3].y - pinky.points[0].y, 5,
        "Fold back toward the palm as in the reference photos")
      XCTAssertGreaterThan(
        simd_distance(pinky.points[3], pinky.points[0]), pinky.lengths.reduce(0, +) * 0.45)
      XCTAssertGreaterThan(pinky.angles.reduce(0, +), 3)
      XCTAssertLessThan(pinky.angles.reduce(0, +), 3.8)
      let hand = try GripHandAsset.load()
      let pinkySkin = hand.vertices.indices.filter { i in
        pinky.finger.jointNames.reduce(0.0) { total, name in
          total + hand.weights[i][hand.joints.firstIndex { $0.name == name }!]
        } > 0.7
      }
      XCTAssertGreaterThan(
        pinkySkin.map { simd_distance(pose.vertices[$0], pose.ballCenter) - 36.5 }.min()!, 0.5)
    }
  }

  func testReferenceHandPreservesAuthoredPalmVolumeAndNaturalDigitSpacing() throws {
    let profile = try SampleHandProfiles.averageRight()
    let hand = try GripHandAsset.load()
    let pose = try GripPoseSolver.openHand(profile: profile)
    let core = hand.vertices.indices.filter {
      abs(hand.vertices[$0][0]) < 10 && (30...50).contains(hand.vertices[$0][1])
    }
    let depths = core.map { pose.vertices[$0].z }
    let thickness = depths.max()! - depths.min()!
    let sourceDepths = core.map { hand.vertices[$0][2] }
    let sourceThickness = sourceDepths.max()! - sourceDepths.min()!
    XCTAssertGreaterThan(
      thickness, sourceThickness * 0.85,
      "Unknown thickness must preserve the supplied palm, not force a 14 mm sheet")
    XCTAssertLessThan(thickness, sourceThickness * 1.15)
    let fingers = [GripFinger.index, .middle, .ring, .pinky].map { f in
      pose.fingers.first { $0.finger == f }!
    }
    for i in 0..<3 {
      let a = fingers[i]
      let b = fingers[i + 1]
      let rootGap = abs(a.points[0].x - b.points[0].x) - (a.radius + b.radius)
      XCTAssertGreaterThan(
        rootGap, -0.5, "Small overlap of approximate cylinders is not a skin collision")
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
    let adjustedThickness = measuredDepths.max()! - measuredDepths.min()!
    XCTAssertLessThan(adjustedThickness, thickness)
    XCTAssertGreaterThan(
      adjustedThickness, thickness * 0.8,
      "An uncertain scan must not flatten the authored palm")
    XCTAssertTrue(actual.diagnostics.adjustedProportions)
  }

  func testUnusualScannedLengthsStayBoundedWithoutChangingTheProfile() throws {
    let sample = try SampleHandProfiles.averageRight()
    func enlarged(_ value: FingerMeasurements) -> FingerMeasurements {
      FingerMeasurements(segmentsMm: value.segmentsMm.map { $0 * 1.4 }, diameterMm: nil)
    }
    let f = sample.measurements.fingers
    let profile = HandProfile(
      profileId: "bounded", createdAt: sample.createdAt, handedness: .right,
      measurements: HandMeasurements(
        palm: sample.measurements.palm,
        fingers: FingerMeasurementSet(
          index: enlarged(f.index), middle: enlarged(f.middle),
          ring: enlarged(f.ring), pinky: enlarged(f.pinky), thumb: enlarged(f.thumb))),
      landmarks: [:], capture: sample.capture)
    let hand = try GripHandAsset.load()
    let pose = try GripPoseSolver.openHand(profile: profile)
    XCTAssertTrue(pose.diagnostics.adjustedProportions)
    for finger in pose.fingers {
      let reference = finger.finger.jointNames.map { name in
        gv(hand.joints.first { $0.name == name }!.position)
      }
      for i in 0..<3 {
        let length = simd_distance(reference[i], reference[i + 1])
        XCTAssertGreaterThanOrEqual(finger.lengths[i], length * 0.8 - 0.001)
        XCTAssertLessThanOrEqual(finger.lengths[i], length * 1.2 + 0.001)
      }
    }
    XCTAssertEqual(
      profile.measurements.fingers.index.segmentsMm, f.index.segmentsMm.map { $0 * 1.4 })
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
