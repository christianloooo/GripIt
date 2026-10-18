import XCTest

@testable import GripItScannerCore

final class SampleThrowStackTests: XCTestCase {
  func testAddsOneSampleAtATimeAndRetainsEarlierThrows() {
    let first = ThrowSessionDraft().appendingSampleThrow()
    let second = first.appendingSampleThrow()
    let third = second.appendingSampleThrow()
    XCTAssertEqual(first.source, .sample)
    XCTAssertEqual(first.rows.count, 1)
    XCTAssertEqual(second.rows.count, 2)
    XCTAssertEqual(third.rows.count, 3)
    XCTAssertEqual(third.rows[0], first.rows[0])
    XCTAssertEqual(third.rows[1], second.rows[1])
    XCTAssertEqual(third.rows.map(\.velocityMph), ThrowSessionDraft.sample().rows.map(\.velocityMph))
    XCTAssertEqual(Set(third.rows.map(\.id)).count, 3)
  }

  func testUsesAnEmptyRowAndCyclesExistingSamplesWithoutInventingValues() {
    var session = ThrowSessionDraft.sample()
    session.rows.append(ThrowDraft(source: .sample))
    let added = session.appendingSampleThrow()
    XCTAssertEqual(added.rows.count, 4)
    XCTAssertEqual(added.rows[3].velocityMph, session.rows[0].velocityMph)
    XCTAssertEqual(added.rows[3].totalSpinRpm, session.rows[0].totalSpinRpm)
    XCTAssertNotEqual(added.rows[3].id, session.rows[0].id)
    XCTAssertTrue(added.rows.allSatisfy { $0.id.hasPrefix("sample-") })
  }

  func testReplacingManualSessionKeepsItsOriginalValueSeparate() {
    var personal = ThrowSessionDraft()
    personal.rows[0].velocityMph = "90"
    let sample = personal.appendingSampleThrow()
    XCTAssertEqual(personal.source, .manual)
    XCTAssertEqual(personal.rows[0].velocityMph, "90")
    XCTAssertEqual(sample.source, .sample)
    XCTAssertEqual(sample.rows.count, 1)
    XCTAssertNotEqual(sample.sessionId, personal.sessionId)
    XCTAssertEqual(sample.rows[0].velocityMph, ThrowSessionDraft.sample().rows[0].velocityMph)
  }
}
