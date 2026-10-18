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
      XCTAssertEqual(Set(zones.map(\.zoneId)).count, 7)
      XCTAssertTrue(zones.contains { $0.zoneId == .palm })
      let thumb = try XCTUnwrap(zones.first { $0.zoneId == .thumbPad })
      XCTAssertEqual(
        thumb.placement?.opposes,
        pitch == .circleChange
          ? [.middlePad, .ringSide] : pitch == .slider ? [.middlePad] : [.indexPad, .middlePad])
      for zone in zones {
        XCTAssertNotNil(
          zone.highlight, "Every demo instruction must declare how its surface highlights")
      }
      XCTAssertEqual(zones.first { $0.zoneId == .wrist }?.highlight?.region, .wrist)
      XCTAssertEqual(zones.first { $0.zoneId == .wrist }?.highlight?.kind, .stabilization)
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
    XCTAssertEqual(change.first { $0.zoneId == .wrist }?.pressure, .medium)
    XCTAssertEqual(change.first { $0.zoneId == .wrist }?.role, .support)
    XCTAssertEqual(change.first { $0.zoneId == .ringSide }?.placement?.surface, .pad)
    XCTAssertEqual(change.first { $0.zoneId == .ringSide }?.role, .drive)
    XCTAssertEqual(change.first { $0.zoneId == .indexPad }?.placement?.surface, .curl)
    XCTAssertEqual(change.first { $0.zoneId == .palm }?.role, .support)
  }
  func testSerializedHighlightDrivesIntensityAndLegacyPlansStillDecode() throws {
    var payload: [String: Any] = [
      "zoneId": "wrist", "instruction": "Keep the wrist steady", "pressure": "none",
      "role": "support", "reach": "comfortable",
      "highlight": ["region": "wrist", "intensity": "medium", "kind": "stabilization"],
    ]
    let record = try JSONDecoder().decode(
      GripZonePlan.self, from: JSONSerialization.data(withJSONObject: payload))
    XCTAssertEqual(record.highlight?.intensity, .medium)
    XCTAssertEqual(record.pressure, .medium, "The new highlight record is authoritative")
    payload.removeValue(forKey: "highlight")
    payload["pressure"] = "firm"
    let legacy = try JSONDecoder().decode(
      GripZonePlan.self, from: JSONSerialization.data(withJSONObject: payload))
    XCTAssertEqual(legacy.highlight?.region, .wrist)
    XCTAssertEqual(legacy.highlight?.intensity, .firm)
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
    let hand = try GripHandAsset.load()
    var vertices = pose.vertices
    for i in GripPoseSolver.padIndices(hand: hand, finger: .index) {
      vertices[i] += simd_normalize(vertices[i] - pose.ballCenter) * 20
    }
    let failed = GripPose(
      pitch: pose.pitch, handedness: pose.handedness, ballCenter: pose.ballCenter,
      ballRotation: pose.ballRotation, fingers: pose.fingers, vertices: vertices,
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
    let encodedZones = try XCTUnwrap(json["zones"] as? [[String: Any]])
    XCTAssertTrue(encodedZones.allSatisfy { $0["highlight"] is [String: Any] })
    let decoded = try JSONDecoder().decode(GripPlan.self, from: data)
    XCTAssertEqual(decoded.zones.map(\.highlight), plan.zones.map(\.highlight))
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
      // Audit each instruction in isolation: another nearby green zone cannot
      // accidentally make a missing wrist, side, curl, or palm instruction pass.
      let encoded = try JSONEncoder().encode(plan)
      let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
      for zone in plan.zones where zone.pressure != GripPressure.none {
        var payload = original
        var zones = try XCTUnwrap(payload["zones"] as? [[String: Any]])
        for i in zones.indices where zones[i]["zoneId"] as? String != zone.zoneId.rawValue {
          zones[i]["pressure"] = "none"
          var highlight = zones[i]["highlight"] as! [String: Any]
          highlight["intensity"] = "none"
          zones[i]["highlight"] = highlight
        }
        payload["zones"] = zones
        let isolated = try JSONDecoder().decode(
          GripPlan.self, from: JSONSerialization.data(withJSONObject: payload))
        let weights = GripPoseSolver.pressureShadingWeights(hand: hand, pose: pose, plan: isolated)
        XCTAssertGreaterThan(weights.max()!, 0.1, "Missing highlight: \(pitch) \(zone.zoneId)")
        XCTAssertGreaterThan(
          weights.filter { $0 > 0.08 }.count, 30, "Instruction needs a visible surface region")
        if zone.zoneId == .wrist {
          let minimum = hand.vertices.indices.filter { hand.vertices[$0][1] < -8 }.map {
            weights[$0]
          }.min()!
          XCTAssertGreaterThan(
            minimum, pitch == .circleChange ? 0.6 : 0.95,
            "The entire wrist circumference must highlight, including the back")
        }
      }
      let wrist = GripZoneSurface.zones.firstIndex(of: .wrist)!
      let palm = GripZoneSurface.zones.firstIndex(of: .palm)!
      XCTAssertFalse(surface.weights.contains { $0[wrist] > 0.4 && $0[palm] > 0.4 })
      XCTAssertTrue(
        surface.weights.flatMap { $0 }.allSatisfy { $0.isFinite && (0...1).contains($0) })
    }
  }
}
