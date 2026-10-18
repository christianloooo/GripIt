import Foundation
import XCTest

@testable import GripItScannerCore

final class RapsodoPhotoFixtureTests: XCTestCase {
  func testPhotoFeedbackRespectsTheActualFittedHand() throws {
    let pose = try GripPoseSolver.solve(profile: SampleHandProfiles.averageRight(), pitch: .fourSeam)
    let plan = GripPlan(pose: pose)
    var draft = ThrowSessionDraft(source: .sample)
    draft.rows = [RapsodoPhotoFixture.baseball.makeDraft()]
    let records = try NativeFocusEngine.records(draft, pitch: .fourSeam, profileId: "fitted-photo")
    let assessment = try NativeFocusEngine.assess(pitch: .fourSeam, records: records,
      zones: plan.zones, gripPlanId: "fitted-photo")
    print("FITTED_PHOTO_PATH: \(assessment.feedbackKind ?? "missing"), zones=\(assessment.zones.map { $0.zoneId.rawValue })")
    for zone in assessment.zones where zone.severity != .green {
      XCTAssertEqual(plan.zones.first { $0.zoneId == zone.zoneId }?.reach, .comfortable)
    }
    if assessment.feedbackKind == "fit" {
      XCTAssertTrue(assessment.zones.isEmpty)
      XCTAssertNil(assessment.changeToTry)
    } else {
      XCTAssertEqual(assessment.nextAction.zoneId, .thumbPad)
      XCTAssertEqual(assessment.zones.first { $0.zoneId == .thumbPad }?.severity, .red)
    }
  }

  func testBothCapturesReachFeedbackWithoutInventedHeightOrLostSource() throws {
    for capture in RapsodoPhotoFixture.allCases {
      let draft = capture.makeDraft()
      XCTAssertTrue(draft.releaseHeightFeet.isEmpty)
      var session = ThrowSessionDraft(source: .sample)
      session.rows = [draft]
      let records = try NativeFocusEngine.records(session, pitch: .fourSeam, profileId: "photo-hand")
      XCTAssertEqual(records.count, 1)
      XCTAssertEqual(records[0].source, .sample)
      XCTAssertNil(records[0].measurements.releaseHeightFeet)
      let encoded = try JSONEncoder().encode(records[0])
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
      let readings = try XCTUnwrap(object["measurements"] as? [String: Any])
      XCTAssertTrue(readings["releaseHeightFeet"] is NSNull)
      let assessment = try NativeFocusEngine.assess(pitch: .fourSeam, records: records,
        zones: PitchGrip.fourSeam.zoneTemplates, gripPlanId: "photo-plan")
      XCTAssertEqual(assessment.ruleVersion, "demo-rules-1")
      XCTAssertNotNil(assessment.changeToTry)
      XCTAssertTrue(assessment.zones.contains { $0.severity == .red })
      XCTAssertFalse(assessment.zones.contains { $0.zoneId == .wrist })
    }
  }

  func testOnlyExactBundledPhotosReceiveSavedReadings() throws {
    for capture in RapsodoPhotoFixture.allCases {
      let image = try Data(contentsOf: XCTUnwrap(capture.imageURL))
      let preview = try Data(contentsOf: XCTUnwrap(capture.previewURL))
      XCTAssertEqual(RapsodoPhotoFixture.matching(image), capture)
      XCTAssertEqual(RapsodoPhotoFixture.matching(preview), capture)
    }
    XCTAssertNil(RapsodoPhotoFixture.matching(Data("unrelated upload".utf8)))
  }
}
