import XCTest
@testable import GripItScannerCore

final class RecentDepthLandmarksTests: XCTestCase {
    func testBriefDepthHoleUsesOnlyRecentMeasuredPointInSameSteadyView() {
        var history = RecentDepthLandmarks()
        let full = fixtureObservation(view: .palm).landmarks
        var first = full
        first.removeValue(forKey: .indexTip)
        XCTAssertEqual(history.record(first, view: .palm, timestamp: 1).count, 20)
        var second = full
        second.removeValue(forKey: .pinkyTip)
        let merged = history.record(second, view: .palm, timestamp: 1.125)
        XCTAssertEqual(merged.count, 21)
        XCTAssertEqual(merged[.pinkyTip], first[.pinkyTip])
    }

    func testOldOrWrongViewPointsCannotCompleteCoverage() {
        var history = RecentDepthLandmarks()
        let full = fixtureObservation(view: .palm).landmarks
        _ = history.record(full, view: .palm, timestamp: 1)
        var partial = full
        partial.removeValue(forKey: .indexTip)
        XCTAssertEqual(history.record(partial, view: .palm, timestamp: 2).count, 20)
        _ = history.record(full, view: .palm, timestamp: 3)
        XCTAssertEqual(history.record(partial, view: .thumbSide, timestamp: 3.1).count, 20)
    }

    func testMovementAndTrackingLossInvalidateHistoricalDepth() {
        var history = RecentDepthLandmarks()
        let full = fixtureObservation(view: .palm).landmarks
        _ = history.record(full, view: .palm, timestamp: 1)
        var moved = fixtureObservation(view: .palm, offset: (20, 0, 0)).landmarks
        moved.removeValue(forKey: .indexTip)
        XCTAssertEqual(history.record(moved, view: .palm, timestamp: 1.125).count, 20)
        XCTAssertTrue(history.record([:], view: .palm, timestamp: 1.25).isEmpty)
        XCTAssertEqual(history.record(moved, view: .palm, timestamp: 1.375).count, 20)
    }
}
