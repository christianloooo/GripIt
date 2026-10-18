import XCTest
import simd

@testable import GripItScannerCore

final class GripPlanTests: XCTestCase {
  func testExactPitchAndZoneContracts() throws {
    XCTAssertEqual(
      PitchGrip.allCases.map(\.rawValue), ["four-seam", "two-seam", "slider", "changeup"])
    XCTAssertEqual(
      GripZoneID.allCases.map(\.rawValue),
      ["index-pad", "middle-pad", "ring-side", "pinky", "thumb-pad", "palm", "wrist"])
    for pitch in PitchGrip.allCases {
      let zones = pitch.zoneTemplates
      XCTAssertEqual(Set(zones.map(\.zoneId)).count, pitch == .slider ? 6 : 7)
      XCTAssertEqual(zones.contains { $0.zoneId == .palm }, pitch != .slider)
      let thumb = try XCTUnwrap(zones.first { $0.zoneId == .thumbPad })
      XCTAssertEqual(
        thumb.placement?.opposes,
        pitch == .circleChange
          ? [.indexPad] : pitch == .slider ? [.middlePad] : [.indexPad, .middlePad])
      XCTAssertEqual(zones.first { $0.zoneId == .wrist }?.extrapolated, true)
      for zone in zones where zone.placement?.seam == .across || zone.placement?.seam == .along {
        XCTAssertEqual(zone.placement?.seamOffsetMm, 0)
      }
    }
    let four = PitchGrip.fourSeam.zoneTemplates
    XCTAssertEqual(four.first { $0.zoneId == .middlePad }?.pressure, .firm)
    XCTAssertEqual(four.first { $0.zoneId == .palm }?.pressure, GripPressure.none)
    XCTAssertEqual(four.first { $0.zoneId == .indexPad }?.placement?.seam, .across)
    XCTAssertEqual(
      PitchGrip.twoSeam.zoneTemplates.first { $0.zoneId == .indexPad }?.placement?.seam, .along)
    let slider = PitchGrip.slider.zoneTemplates
    XCTAssertEqual(slider.first { $0.zoneId == .indexPad }?.placement?.seam, .beside)
    XCTAssertEqual(slider.first { $0.zoneId == .indexPad }?.role, .support)
    let change = PitchGrip.circleChange.zoneTemplates
    XCTAssertNil(change.first { $0.zoneId == .wrist }?.pressure)
    XCTAssertNil(change.first { $0.zoneId == .wrist }?.role)
    XCTAssertEqual(change.first { $0.zoneId == .ringSide }?.placement?.surface, .pad)
    XCTAssertEqual(change.first { $0.zoneId == .ringSide }?.role, .drive)
    XCTAssertEqual(change.first { $0.zoneId == .indexPad }?.placement?.surface, .curl)
    XCTAssertEqual(change.first { $0.zoneId == .palm }?.role, .support)
  }
  func testSeverityUsesNumericMapAndDoesNotConfuseMissingWithGreen() throws {
    let map = GripSeverityMap([
      "index-pad": -1, "middle-pad": 0.2, "ring-side": 0.5, "wrist": 5, "palm": .nan,
      "thumb-pad": .infinity, "unknown": 0.1,
    ])
    XCTAssertEqual(map[.indexPad], 0)
    XCTAssertEqual(map[.wrist], 1)
    XCTAssertNil(map[.palm])
    XCTAssertNil(map[.pinky])
    XCTAssertNil(map[.thumbPad])
    XCTAssertNil(GripSeverityBand.band(nil))
    XCTAssertNil(GripSeverityBand.band(.nan))
    XCTAssertEqual(GripSeverityBand.band(0), .green)
    XCTAssertEqual(GripSeverityBand.band(0.1999), .green)
    XCTAssertEqual(GripSeverityBand.band(0.2), .yellow)
    XCTAssertEqual(GripSeverityBand.band(0.4999), .yellow)
    XCTAssertEqual(GripSeverityBand.band(0.5), .red)
    XCTAssertEqual(GripSeverityBand.band(1), .red)
    let encoded = try JSONEncoder().encode(map)
    XCTAssertEqual(try JSONDecoder().decode(GripSeverityMap.self, from: encoded), map)
    XCTAssertNotNil(try JSONSerialization.jsonObject(with: encoded) as? [String: Double])
  }
  func testPlanReportsMeasuredGeometricErrorAndRoundTrips() throws {
    let pose = try GripPoseSolver.solve(
      profile: SampleHandProfiles.averageRight(), pitch: .fourSeam)
    let plan = GripPlan(pose: pose)
    for zone in plan.zones where zone.zoneId != .wrist {
      XCTAssertNotNil(zone.shortfallMm)
      XCTAssertTrue(zone.shortfallMm!.isFinite)
      XCTAssertEqual(zone.reach, GripReach.classify(shortfallMm: zone.shortfallMm!))
    }
    var fingers = pose.fingers
    let index = try XCTUnwrap(fingers.firstIndex { $0.finger == .index })
    fingers[index].targetError = 20
    let failed = GripPose(
      pitch: pose.pitch, handedness: pose.handedness, ballCenter: pose.ballCenter,
      ballRotation: pose.ballRotation, fingers: fingers, vertices: pose.vertices,
      indices: pose.indices, diagnostics: pose.diagnostics)
    XCTAssertEqual(
      GripPlan(pose: failed).zones.first { $0.zoneId == .indexPad }?.reach, .unreachable)
    XCTAssertEqual(GripReach.classify(shortfallMm: 3), .comfortable)
    XCTAssertEqual(GripReach.classify(shortfallMm: 3.01), .strained)
    XCTAssertEqual(GripReach.classify(shortfallMm: 8), .strained)
    XCTAssertEqual(GripReach.classify(shortfallMm: 8.01), .unreachable)
    let data = try JSONEncoder().encode(plan)
    XCTAssertEqual(
      try JSONDecoder().decode(GripPlan.self, from: data).zones.map(\.zoneId),
      plan.zones.map(\.zoneId))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual((json["zones"] as? [[String: Any]])?.first?["title"] as? String, "Index finger")
  }
  func testEveryApplicableZoneOwnsRealSurfaceAndSelectableFaces() throws {
    let hand = try GripHandAsset.load()
    for pitch in PitchGrip.allCases {
      let pose = try GripPoseSolver.solve(profile: SampleHandProfiles.averageRight(), pitch: pitch)
      let plan = GripPlan(pose: pose)
      let surface = GripZoneSurface(pose: pose, gripPlan: plan, hand: hand)
      for zone in plan.zones {
        let zi = GripZoneSurface.zones.firstIndex(of: zone.zoneId)!
        XCTAssertGreaterThan(surface.weights.map { $0[zi] }.max()!, 0.4, zone.zoneId.rawValue)
        let face = stride(from: 0, to: pose.indices.count, by: 3).first { face in
          (0..<3).allSatisfy { surface.picking[Int(pose.indices[face + $0])] == zone.zoneId }
        }
        XCTAssertNotNil(face, zone.zoneId.rawValue)
        if let face {
          XCTAssertEqual(
            surface.zone(
              face: face / 3, barycentric: SIMD3(repeating: 1.0 / 3), indices: pose.indices),
            zone.zoneId)
        }
      }
      if pitch == .slider {
        XCTAssertFalse(surface.picking.contains(.palm))
        let palm = GripZoneSurface.zones.firstIndex(of: .palm)!
        XCTAssertTrue(surface.weights.allSatisfy { $0[palm] == 0 })
      }
      let wrist = GripZoneSurface.zones.firstIndex(of: .wrist)!
      let palm = GripZoneSurface.zones.firstIndex(of: .palm)!
      XCTAssertFalse(surface.weights.contains { $0[wrist] > 0.4 && $0[palm] > 0.4 })
      XCTAssertTrue(
        surface.weights.flatMap { $0 }.allSatisfy { $0.isFinite && (0...1).contains($0) })
    }
  }
}
