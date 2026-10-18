import XCTest
@testable import GripItScannerCore

final class ScannerSessionTests: XCTestCase {
    func testRejectedGeometryDoesNotAdvanceCoverage() {
        var session = ScannerSession(minimumFramesPerView: 1)
        let wristOnly = ScanObservation(
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

        XCTAssertThrowsError(try session.accept(wristOnly))
        XCTAssertEqual(session.coverage.snapshot.fraction, 0)
        XCTAssertEqual(session.coverage.snapshot.currentView, .palm)
    }

    func testIncompleteSessionCannotExport() {
        let session = ScannerSession(minimumFramesPerView: 1)

        XCTAssertThrowsError(try session.makeProfile(
            profileId: "profile-1",
            createdAt: "2026-10-17T00:00:00Z"
        ))
    }

    func testCompletedSessionExportsCanonicalV1Profile() throws {
        var session = ScannerSession(minimumFramesPerView: 1)
        for view in ScanView.requiredOrder {
            try session.accept(fixtureObservation(
                view: view,
                offset: (120, -30, 500)
            ))
        }

        let profile = try session.makeProfile(
            profileId: "profile-1",
            createdAt: "2026-10-17T00:00:00Z"
        )

        XCTAssertEqual(profile.coordinateSystem, "gripit-hand-v1")
        XCTAssertEqual(profile.capture.coverage.fraction, 1)
        XCTAssertEqual(profile.landmarks["wrist"]?.xMm, 0)
        XCTAssertEqual(profile.landmarks["wrist"]?.yMm, 0)
        XCTAssertEqual(profile.landmarks["wrist"]?.zMm, 0)
    }
}
