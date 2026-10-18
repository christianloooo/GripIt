import Foundation
import XCTest

@testable import GripItScannerCore

final class TrainingFlowTests: XCTestCase {
  func testEntryValidationUsesExistingRulesAndClockFormat() throws {
    var row = ThrowSessionDraft.sample().rows[0]
    let valid = try NativeFocusEngine.validate(row)
    XCTAssertTrue(valid.errors.isEmpty)
    XCTAssertEqual(valid.measurements?.spinDirectionClock, 12.5)
    row.velocityMph = "900"
    row.spinDirectionClock = "13:60"
    row.spinEfficiencyPercent = "101"
    let invalid = try NativeFocusEngine.validate(row)
    XCTAssertNil(invalid.measurements)
    XCTAssertNotNil(invalid.errors["velocityMph"])
    XCTAssertNotNil(invalid.errors["spinDirectionClock"])
    XCTAssertNotNil(invalid.errors["spinEfficiencyPercent"])
  }

  func testSampleEditsRemainSampleAndNullsAreExplicit() throws {
    var draft = ThrowSessionDraft.sample()
    draft.rows[0].velocityMph = "84"
    let records = try NativeFocusEngine.records(draft, pitch: .fourSeam, profileId: "my-hand")
    XCTAssertEqual(records.count, 3)
    XCTAssertTrue(records.allSatisfy { $0.source == .sample && $0.throwId.hasPrefix("sample-") })
    let encoded = try JSONEncoder().encode(records[0])
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let measures = try XCTUnwrap(object["measurements"] as? [String: Any])
    XCTAssertNotNil(measures["gyroDegree"] as? Double)
    XCTAssertEqual(measures["horizontalBreakInches"] as? Double, 18.6)
    XCTAssertEqual(measures["verticalBreakInches"] as? Double, 13.8)
    XCTAssertTrue(measures["rapsodoScore"] is NSNull)
    XCTAssertEqual(
      records[0].extensions["gripit.throwEntry"], .object(["handProfileId": .string("my-hand")]))
    let real = ThrowSessionDraft()
    XCTAssertEqual(real.source, .manual)
    XCTAssertFalse(real.sessionId.hasPrefix("sample-"))
    XCTAssertTrue(real.rows[0].velocityMph.isEmpty)
  }

  func testIndependentSpinReadingsDeriveMissingValueAndPreserveBoth() throws {
    var row = ThrowSessionDraft.sample().rows[0]
    row.spinEfficiencyPercent = ""
    row.gyroDegree = "-45"
    row.rapsodoScore = "0"
    let values = try XCTUnwrap(NativeFocusEngine.validate(row).measurements)
    XCTAssertEqual(try XCTUnwrap(values.spinEfficiencyPercent), cos(.pi / 4) * 100, accuracy: 0.000_001)
    XCTAssertEqual(values.gyroDegree, -45)
    XCTAssertEqual(values.rapsodoScore, 0)

    row.spinEfficiencyPercent = "95"
    row.gyroDegree = "-18.2"
    let both = try XCTUnwrap(NativeFocusEngine.validate(row).measurements)
    XCTAssertEqual(both.spinEfficiencyPercent, 95)
    XCTAssertEqual(both.gyroDegree, -18.2)
  }

  func testMayaExampleAndUntintedZones() throws {
    var draft = ThrowSessionDraft.sample()
    draft.rows = [draft.rows[0]]
    draft.rows[0].spinEfficiencyPercent = "72"
    draft.rows[0].gyroDegree = ""
    let records = try NativeFocusEngine.records(draft, pitch: .fourSeam, profileId: "my-hand")
    let assessment = try NativeFocusEngine.assess(
      pitch: .fourSeam, records: records,
      zones: PitchGrip.fourSeam.zoneTemplates, gripPlanId: "my-plan")
    XCTAssertEqual(assessment.gripPlanId, "my-plan")
    XCTAssertEqual(assessment.nextAction.zoneId, .wrist)
    XCTAssertEqual(assessment.confidence, 0.55)
    XCTAssertEqual(assessment.zones.first { $0.zoneId == .wrist }?.severity, .red)
    XCTAssertEqual(assessment.zones.first { $0.zoneId == .indexPad }?.severity, .yellow)
    XCTAssertNil(assessment.severityMap[.pinky])
    XCTAssertEqual(assessment.throwIds, records.map(\.throwId))
    XCTAssertTrue(assessment.prototypeAdvice)
    XCTAssertNil(assessment.consistency)
  }

  func testRealReachLimitsSuppressTechniqueAdvice() throws {
    var zones = PitchGrip.fourSeam.zoneTemplates
    for i in zones.indices { zones[i].reach = .unreachable }
    let records = try NativeFocusEngine.records(.sample(), pitch: .fourSeam, profileId: "p")
    let result = try NativeFocusEngine.assess(
      pitch: .fourSeam, records: records, zones: zones, gripPlanId: "p")
    XCTAssertTrue(result.zones.isEmpty)
    XCTAssertNil(result.nextAction.zoneId)
    XCTAssertEqual(Set(result.unreachableZones), Set(zones.map(\.zoneId)))
  }

  func testReleaseDriftAcrossThreeThrowsDoesNotColorHand() throws {
    var draft = ThrowSessionDraft.sample()
    draft.rows[0].releaseHeightFeet = "5"
    draft.rows[1].releaseHeightFeet = "6"
    let records = try NativeFocusEngine.records(draft, pitch: .fourSeam, profileId: "p")
    let result = try NativeFocusEngine.assess(
      pitch: .fourSeam, records: records,
      zones: PitchGrip.fourSeam.zoneTemplates, gripPlanId: "p")
    XCTAssertEqual(result.classification, "not-grip")
    XCTAssertTrue(result.zones.isEmpty)
    XCTAssertEqual(result.nextAction.summary, "Steady your release point")
    XCTAssertNotNil(result.consistency)
  }

  func testOtherPitchesDoNotReceiveFastballAdviceAndMismatchesAreRejected() throws {
    let records = try NativeFocusEngine.records(.sample(), pitch: .circleChange, profileId: "p")
    let result = try NativeFocusEngine.assess(
      pitch: .circleChange, records: records,
      zones: PitchGrip.circleChange.zoneTemplates, gripPlanId: "p")
    XCTAssertTrue(result.zones.isEmpty)
    XCTAssertEqual(result.nextAction.summary, "Compare against your fastball")
    XCTAssertThrowsError(
      try NativeFocusEngine.assess(
        pitch: .slider, records: records,
        zones: PitchGrip.slider.zoneTemplates, gripPlanId: "p"))
    XCTAssertThrowsError(
      try NativeFocusEngine.records(ThrowSessionDraft(), pitch: .fourSeam, profileId: "p"))
  }
}
