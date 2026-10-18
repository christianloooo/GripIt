import XCTest
@testable import GripItScannerCore

final class MetricGeometryTests: XCTestCase {
    func testProjectsDepthIntoMillimeters() throws {
        let point = try DepthProjector.project(
            pixel: PixelPoint(x: 420, y: 290),
            depthMeters: 0.5,
            intrinsics: CameraIntrinsics(fx: 500, fy: 500, cx: 320, cy: 240)
        )

        XCTAssertEqual(point, MetricPoint3D(xMm: 100, yMm: 50, zMm: 500))
    }

    func testRejectsOutOfRangeDepth() {
        XCTAssertThrowsError(try DepthProjector.project(
            pixel: PixelPoint(x: 0, y: 0),
            depthMeters: 0.05,
            intrinsics: CameraIntrinsics(fx: 500, fy: 500, cx: 320, cy: 240)
        ))
    }

    func testLeftHandReflectsXOnly() {
        let point = MetricPoint3D(xMm: -12, yMm: 30, zMm: 4)
        XCTAssertEqual(
            HandCanonicalizer.canonicalize(point, handedness: .left),
            MetricPoint3D(xMm: 12, yMm: 30, zMm: 4)
        )
    }

    func testMirroredHandsProduceIdenticalCanonicalLandmarks() throws {
        let right = fixtureObservation(view: .palm, handedness: .right)
        let leftLandmarks = right.landmarks.mapValues { landmark in
            NamedLandmark(
                name: landmark.name,
                point: MetricPoint3D(
                    xMm: -landmark.point.xMm,
                    yMm: landmark.point.yMm,
                    zMm: landmark.point.zMm
                ),
                confidence: landmark.confidence
            )
        }
        let left = ScanObservation(
            view: .palm,
            handedness: .left,
            landmarks: leftLandmarks,
            frameConfidence: 1
        )

        let canonicalRight = try right.canonicalized()
        let canonicalLeft = try left.canonicalized()
        for name in HandLandmarkName.allCases {
            XCTAssertEqual(
                try XCTUnwrap(canonicalRight.landmarks[name]?.point.xMm),
                try XCTUnwrap(canonicalLeft.landmarks[name]?.point.xMm),
                accuracy: 0.000_001
            )
            XCTAssertEqual(
                try XCTUnwrap(canonicalRight.landmarks[name]?.point.yMm),
                try XCTUnwrap(canonicalLeft.landmarks[name]?.point.yMm),
                accuracy: 0.000_001
            )
            XCTAssertEqual(
                try XCTUnwrap(canonicalRight.landmarks[name]?.point.zMm),
                try XCTUnwrap(canonicalLeft.landmarks[name]?.point.zMm),
                accuracy: 0.000_001
            )
        }
    }
}
