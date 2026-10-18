import XCTest
import GripItScannerCore
@testable import GripIt

final class ScannerAdapterTests: XCTestCase {
    func testPortraitPointsMapToNativeSensorCorners() {
        let topLeft = SensorImageRotation.left.sensorPoint(fromModel: PixelPoint(x: 0, y: 0))
        XCTAssertEqual(topLeft.x, 1)
        XCTAssertEqual(topLeft.y, 0)
        let bottomRight = SensorImageRotation.left.sensorPoint(fromModel: PixelPoint(x: 1, y: 1))
        XCTAssertEqual(bottomRight.x, 0)
        XCTAssertEqual(bottomRight.y, 1)
    }

    func testDepthHolesAndOutOfRangeSamplesCannotBecomeMeasurements() {
        XCTAssertNil(ScannerAdapterGeometry.medianValidDepth([.nan, 0, 3]))
        XCTAssertEqual(ScannerAdapterGeometry.medianValidDepth([0, .nan, 0.39, 0.4, 0.41]), 0.4)
    }

    func testMirroredHandsClassifyPalmConsistently() {
        XCTAssertEqual(ScannerAdapterGeometry.classifyView(normalX: 0, normalZ: -1, handedness: .right), .palm)
        XCTAssertEqual(ScannerAdapterGeometry.classifyView(normalX: 0, normalZ: 1, handedness: .left), .palm)
    }

    func testCoverageDoesNotFillAnUnobservedView() {
        var coverage = LandmarkCoverageTracker(minimumSamplesPerLandmark: 2)
        coverage.record(validLandmarks: [.wrist], view: .palm)
        XCTAssertEqual(coverage.snapshot.fraction(for: .wrist, in: .palm), 0.5)
        XCTAssertEqual(coverage.snapshot.fraction(for: .wrist, in: .back), 0)
    }

    @MainActor
    func testSampleFlowProducesExportWithoutStartingCamera() throws {
        let model = ScannerViewModel()
        model.loadSample()
        XCTAssertEqual(model.phase, .complete)
        XCTAssertEqual(model.progress, 1)
        XCTAssertFalse(model.captureSession.isRunning)
        let file = try XCTUnwrap(model.exportURL)
        let exported = try HandProfileCodec.decode(Data(contentsOf: file))
        XCTAssertEqual(exported.profileId, "sample-average-right")
        model.reset()
        XCTAssertEqual(model.phase, .chooseHand)
        XCTAssertNil(model.profile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
