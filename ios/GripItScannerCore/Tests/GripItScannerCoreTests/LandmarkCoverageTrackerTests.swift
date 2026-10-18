import XCTest
@testable import GripItScannerCore

final class LandmarkCoverageTrackerTests: XCTestCase {
    func testCoverageCountsValidLandmarksWithoutCompletingMissingOnes() {
        var tracker = LandmarkCoverageTracker(minimumSamplesPerLandmark: 2)

        tracker.record(validLandmarks: [.wrist, .indexMCP], view: .palm)
        tracker.record(validLandmarks: [.wrist], view: .palm)

        XCTAssertEqual(tracker.snapshot.counts[.wrist], 2)
        XCTAssertEqual(tracker.snapshot.counts[.indexMCP], 1)
        XCTAssertEqual(tracker.snapshot.fraction(for: .wrist), 1)
        XCTAssertEqual(tracker.snapshot.fraction(for: .indexMCP), 0.5)
    }

    func testCoverageTracksViewsIndependently() {
        var tracker = LandmarkCoverageTracker(minimumSamplesPerLandmark: 1)

        tracker.record(validLandmarks: [.wrist], view: .palm)

        XCTAssertEqual(tracker.snapshot.fraction(for: .wrist, in: .palm), 1)
        XCTAssertEqual(tracker.snapshot.fraction(for: .wrist, in: .back), 0)
    }

    func testRequiredViewOrderFollowsOneContinuousRotation() {
        XCTAssertEqual(ScanView.requiredOrder, [.palm, .thumbSide, .back, .pinkySide])
    }
}
