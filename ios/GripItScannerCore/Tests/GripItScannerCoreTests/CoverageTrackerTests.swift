import XCTest
@testable import GripItScannerCore

final class CoverageTrackerTests: XCTestCase {
    func testRequiresFourViewsInOrder() throws {
        var tracker = CoverageTracker(minimumFramesPerView: 2, minimumConfidence: 0.8)
        try tracker.accept(fixtureObservation(view: .palm))
        XCTAssertEqual(tracker.snapshot.fraction, 0.125)
        try tracker.accept(fixtureObservation(view: .palm))

        XCTAssertEqual(tracker.snapshot.currentView, .thumbSide)
        XCTAssertEqual(tracker.snapshot.fraction, 0.25)
    }

    func testRejectsLowConfidenceWithoutAdvancing() {
        var tracker = CoverageTracker(minimumFramesPerView: 2, minimumConfidence: 0.8)

        XCTAssertThrowsError(try tracker.accept(fixtureObservation(view: .palm, confidence: 0.5)))
        XCTAssertEqual(tracker.snapshot.fraction, 0)
    }

    func testRejectsPartialLandmarkSet() {
        var tracker = CoverageTracker(minimumFramesPerView: 1, minimumConfidence: 0.8)
        let observation = ScanObservation(
            view: .palm,
            handedness: .right,
            landmarks: [
                .wrist: NamedLandmark(
                    name: .wrist,
                    point: MetricPoint3D(xMm: 0, yMm: 0, zMm: 500),
                    confidence: 1
                ),
            ],
            frameConfidence: 1
        )

        XCTAssertThrowsError(try tracker.accept(observation)) { error in
            XCTAssertEqual(error as? CoverageError, .incompleteLandmarks)
        }
        XCTAssertEqual(tracker.snapshot.fraction, 0)
    }

    func testRejectsConfidenceOutsideUnitRange() {
        var tracker = CoverageTracker(minimumFramesPerView: 1, minimumConfidence: 0.8)

        XCTAssertThrowsError(try tracker.accept(fixtureObservation(view: .palm, confidence: 1.5))) { error in
            XCTAssertEqual(error as? CoverageError, .invalidConfidence)
        }
    }
}
