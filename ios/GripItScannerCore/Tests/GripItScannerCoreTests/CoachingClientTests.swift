import Foundation
import XCTest

@testable import GripItScannerCore

final class CoachingClientTests: XCTestCase {
  private actor Requests {
    var count = 0
    let failFirst: Bool
    init(failFirst: Bool = false) { self.failFirst = failFirst }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
      count += 1
      if failFirst && count == 1 { throw URLError(.timedOut) }
      try await Task.sleep(for: .milliseconds(20))
      if request.url?.path == "/api/ask" {
        return (Data(#"{"answer":"Try this again.","answered":true}"#.utf8), 200)
      }
      return (Data(#"{"detail":"Try this again.","rewritten":true,"fit":"Your measured fit."}"#.utf8), 200)
    }
  }

  func testRepeatedAndConcurrentCoachingSharesOneRequest() async throws {
    let context = try context()
    let requests = Requests()
    let client = CoachingClient(baseURL: URL(string: "https://example.com"), transport: requests.send)
    async let first = client.coach(context)
    async let second = client.coach(context)
    let results = await [first, second]
    XCTAssertTrue(results.allSatisfy(\.rewritten))
    _ = await client.coach(context)
    let count = await requests.count
    XCTAssertEqual(count, 1)
  }

  func testFailureCanRetryAndQuestionsUseDistinctKeys() async throws {
    let context = try context()
    let requests = Requests(failFirst: true)
    let client = CoachingClient(baseURL: URL(string: "https://example.com"), transport: requests.send)
    let failed = await client.coach(context)
    XCTAssertFalse(failed.rewritten)
    let recovered = await client.coach(context)
    XCTAssertTrue(recovered.rewritten)
    _ = await client.ask("Why this finger?", context: context)
    _ = await client.ask("Why this finger?", context: context)
    _ = await client.ask("Why this grip?", context: context)
    let count = await requests.count
    XCTAssertEqual(count, 4)
  }
  private func context() throws -> CoachingContext {
    let records = try NativeFocusEngine.records(.sample(), pitch: .fourSeam, profileId: "p")
    let assessment = try NativeFocusEngine.assess(
      pitch: .fourSeam, records: records,
      zones: PitchGrip.fourSeam.zoneTemplates, gripPlanId: "g")
    return CoachingContext(
      profile: try SampleHandProfiles.averageRight(),
      plan: FocusGripPlan(
        profileId: "p", pitch: .fourSeam, zones: PitchGrip.fourSeam.zoneTemplates,
        gripPlanId: "g"), assessment: assessment, records: records)
  }

  func testExistingCoachEndpointAndMeasuredContext() async throws {
    let context = try context()
    let client = CoachingClient(baseURL: URL(string: "https://example.com")) { request in
      XCTAssertEqual(request.url?.path, "/api/coach")
      XCTAssertEqual(request.httpMethod, "POST")
      let body = try XCTUnwrap(
        JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
      let plan = try XCTUnwrap(body["plan"] as? [String: Any])
      let records = try XCTUnwrap(body["throws"] as? [[String: Any]])
      XCTAssertEqual(records.count, 3)
      let readings = try XCTUnwrap(records.first?["measurements"] as? [String: Any])
      XCTAssertEqual(readings["velocityMph"] as? Double, 82.4)
      XCTAssertEqual(plan["pitchId"] as? String, "four-seam")
      XCTAssertEqual(plan["gripPlanId"] as? String, "g")
      XCTAssertEqual((plan["instructionZones"] as? [Any])?.count, 7)
      let zones = try XCTUnwrap(plan["instructionZones"] as? [[String: Any]])
      let thumb = try XCTUnwrap(zones.first { $0["zoneId"] as? String == "thumb-pad" })
      let placement = try XCTUnwrap(thumb["placement"] as? [String: Any])
      XCTAssertTrue(placement["seamOffsetMm"] is NSNull)
      let fit = try XCTUnwrap(plan["fit"] as? [String: Any])
      XCTAssertTrue(fit["confidence"] is NSNull, "Do not invent fit confidence")
      return (
        Data(
          #"{"detail":"Try this grip again.","rewritten":true,"fit":"Your hand fit explanation."}"#
            .utf8), 200
      )
    }
    let result = await client.coach(context)
    XCTAssertTrue(result.rewritten)
    XCTAssertEqual(result.fit, "Your hand fit explanation.")
  }

  func testOfflineAndInvalidResponsesRetainRuleFeedback() async throws {
    let context = try context()
    let offline = CoachingClient(baseURL: URL(string: "https://example.com")) { _ in
      throw URLError(.notConnectedToInternet)
    }
    let result = await offline.coach(context)
    XCTAssertEqual(result.detail, context.assessment.nextAction.detail)
    XCTAssertFalse(result.rewritten)
    let bad = CoachingClient(baseURL: URL(string: "https://example.com")) { _ in
      (Data(#"{"detail":""}"#.utf8), 200)
    }
    let invalid = await bad.coach(context)
    XCTAssertEqual(invalid.detail, context.assessment.nextAction.detail)
    let absent = await CoachingClient(baseURL: nil).ask("Why?", context: context)
    XCTAssertFalse(absent.answered)
    XCTAssertEqual(absent.reason, "not-configured")
  }

  func testFollowUpUsesExistingAskContractAndHandlesServerErrors() async throws {
    let context = try context()
    let client = CoachingClient(baseURL: URL(string: "https://example.com")) { request in
      XCTAssertEqual(request.url?.path, "/api/ask")
      let body = try XCTUnwrap(
        JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
      XCTAssertEqual(body["question"] as? String, "Why this finger?")
      XCTAssertNotNil(body["profile"])
      XCTAssertNotNil(body["assessment"])
      return (Data(#"{"answer":"Try again.","answered":true}"#.utf8), 503)
    }
    let result = await client.ask("Why this finger?", context: context)
    XCTAssertFalse(result.answered)
    XCTAssertEqual(result.reason, "http-503")
  }

  func testQuestionsOutsideExistingServerLengthLimitsAreNotSent() async throws {
    let context = try context()
    let client = CoachingClient(baseURL: URL(string: "https://example.com")) { _ in
      XCTFail("Invalid questions must not reach the server")
      return (Data(#"{"answer":"Answer","answered":true}"#.utf8), 200)
    }
    let short = await client.ask("Hi", context: context)
    let long = await client.ask(String(repeating: "a", count: 301), context: context)
    XCTAssertFalse(short.answered)
    XCTAssertFalse(long.answered)
  }

  func testSingleThrowAssessmentEncodesNullableConsistency() throws {
    var draft = ThrowSessionDraft.sample()
    draft.rows = [draft.rows[0]]
    let records = try NativeFocusEngine.records(draft, pitch: .fourSeam, profileId: "p")
    let assessment = try NativeFocusEngine.assess(pitch: .fourSeam, records: records,
      zones: PitchGrip.fourSeam.zoneTemplates, gripPlanId: "p")
    let data = try JSONEncoder().encode(assessment)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertTrue(object["consistency"] is NSNull)
  }
}
