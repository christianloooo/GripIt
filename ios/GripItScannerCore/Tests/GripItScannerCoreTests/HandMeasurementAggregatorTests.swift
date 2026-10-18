import XCTest
@testable import GripItScannerCore

final class HandMeasurementAggregatorTests: XCTestCase {
    func testMedianRejectsOneLargeOutlier() throws {
        let measurements = try HandMeasurementAggregator().measure([
            fixtureObservation(view: .palm, scale: 1),
            fixtureObservation(view: .palm, scale: 1.02),
            fixtureObservation(view: .palm, scale: 8),
        ])

        XCTAssertLessThan(try XCTUnwrap(measurements.palm.widthMm), 100)
    }

    func testMissingRequiredLandmarksRemainAnError() {
        let observation = ScanObservation(
            view: .palm,
            handedness: .right,
            landmarks: [:],
            frameConfidence: 1
        )

        XCTAssertThrowsError(try HandMeasurementAggregator().measure([observation])) { error in
            XCTAssertEqual(error as? HandMeasurementError, .missingLandmark(.wrist))
        }
    }
}
