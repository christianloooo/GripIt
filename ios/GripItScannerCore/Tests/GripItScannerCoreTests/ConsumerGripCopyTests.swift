import XCTest
@testable import GripItScannerCore

final class ConsumerGripCopyTests: XCTestCase {
  func testGuideUsesShortActionsAndKeepsSliderIndexRelaxed() {
    XCTAssertEqual(GripGuideCopy.instruction(pitch: .fourSeam, zone: .thumbPad),
      "Rest your thumb under the ball, below the gap between your index and middle fingers.")
    XCTAssertEqual(GripGuideCopy.instruction(pitch: .slider, zone: .indexPad),
      "Rest your index finger lightly beside your middle finger, off the seam.")
    for pitch in PitchGrip.allCases {
      for zone in GripZoneID.allCases {
        let text = GripGuideCopy.instruction(pitch: pitch, zone: zone)
        XCTAssertFalse(text.isEmpty)
        XCTAssertLessThanOrEqual(text.split(separator: " ").count, 24)
        for jargon in ["fleshy", "distal", "equator", "spin axis", "opposes"] {
          XCTAssertFalse(text.lowercased().contains(jargon))
        }
      }
    }
  }

  func testFeedbackExplainsFirstAndSecondaryActionsWithoutReadings() throws {
    var draft = ThrowSessionDraft(source: .sample)
    draft.rows = [RapsodoPhotoFixture.baseball.makeDraft()]
    let records = try NativeFocusEngine.records(draft, pitch: .fourSeam, profileId: "plain")
    let result = try NativeFocusEngine.assess(pitch: .fourSeam, records: records,
      zones: PitchGrip.fourSeam.zoneTemplates, gripPlanId: "plain")
    XCTAssertEqual(result.primaryAction,
      "Rest your thumb under the ball, below the gap between your index and middle fingers.")
    XCTAssertEqual(result.secondaryActions.count, 1, "The two yellow fingers share one adjustment")
    XCTAssertEqual(result.secondaryActions.first?.action,
      "Place your index and middle fingertips on the raised seams.")
    XCTAssertEqual(result.action(for: .middlePad), result.secondaryActions.first?.action)
    XCTAssertFalse(result.primaryAction.contains("1:56"))
    XCTAssertFalse(result.action(for: .middlePad).contains("Spin per mph"))
    XCTAssertTrue(result.measuredSummary?.contains("77.3") == true, "Keep readings available in Details")
  }

  func testFitAndMissingBaselineDoNotSuggestFingerCorrections() throws {
    let records = try NativeFocusEngine.records(.sample(), pitch: .circleChange, profileId: "gate")
    let result = try NativeFocusEngine.assess(pitch: .circleChange, records: records,
      zones: PitchGrip.circleChange.zoneTemplates, gripPlanId: "gate")
    XCTAssertEqual(result.primaryAction, "Record your fastball first so we can compare your changeup.")
    XCTAssertTrue(result.secondaryActions.isEmpty)
    XCTAssertEqual(result.action(for: .indexPad), result.primaryAction)
  }
}
