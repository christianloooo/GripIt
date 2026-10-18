import XCTest
@testable import GripItScannerCore

final class CameraAlignmentTests: XCTestCase {
    func testCameraReportedRotationReplacesFixedPortraitAssumption() {
        XCTAssertEqual(SensorImageRotation(clockwiseDegrees: 0), .up)
        XCTAssertEqual(SensorImageRotation(clockwiseDegrees: 90), .right)
        XCTAssertEqual(SensorImageRotation(clockwiseDegrees: 180), .down)
        XCTAssertEqual(SensorImageRotation(clockwiseDegrees: 270), .left)
        XCTAssertEqual(SensorImageRotation(clockwiseDegrees: 359), .up)
        XCTAssertNil(SensorImageRotation(clockwiseDegrees: .nan))
    }

    func testAllQuarterTurnsRoundTripSensorPoints() {
        let sensor = PixelPoint(x: 0.2, y: 0.3)
        for angle in [0.0, 90, 180, 270] {
            let rotation = SensorImageRotation(clockwiseDegrees: angle)!
            let result = rotation.sensorPoint(fromModel: rotation.modelPoint(fromSensor: sensor))
            XCTAssertEqual(result.x, sensor.x, accuracy: 0.00001)
            XCTAssertEqual(result.y, sensor.y, accuracy: 0.00001)
        }
    }

    func testPreviewUsesTheSameRotationMirroringAndAspectFillAsCamera() throws {
        let center = try XCTUnwrap(ScannerAdapterGeometry.previewPoint(
            sensorPoint: PixelPoint(x: 0.5, y: 0.5), rotation: .right, mirrored: true,
            sourceWidth: 640, sourceHeight: 480, viewWidth: 360, viewHeight: 640
        ))
        XCTAssertEqual(center.x, 180, accuracy: 0.00001)
        XCTAssertEqual(center.y, 320, accuracy: 0.00001)
        let corner = try XCTUnwrap(ScannerAdapterGeometry.previewPoint(
            sensorPoint: PixelPoint(x: 0, y: 0), rotation: .right, mirrored: true,
            sourceWidth: 640, sourceHeight: 480, viewWidth: 360, viewHeight: 640
        ))
        XCTAssertEqual(corner.x, -60, accuracy: 0.00001)
        XCTAssertEqual(corner.y, 0, accuracy: 0.00001)
    }
}
