import XCTest
@testable import GripItScannerCore

/// Facing resolved from TrueDepth measurements rather than from MediaPipe's
/// monocular world landmarks.
///
/// The measured frame is the one `DepthProjector` produces: x right and y down
/// in sensor pixel axes, z the measured distance from the camera in millimetres,
/// always positive and increasing away from the lens. Nothing here depends on a
/// convention defined outside this package.
final class MeasuredHandFacingTests: XCTestCase {
    private func landmarks(
        wrist: (Double, Double, Double), middleMCP: (Double, Double, Double),
        indexMCP: (Double, Double, Double), pinkyMCP: (Double, Double, Double)
    ) -> [HandLandmarkName: MetricPoint3D] {
        func point(_ value: (Double, Double, Double)) -> MetricPoint3D {
            MetricPoint3D(xMm: value.0, yMm: value.1, zMm: value.2)
        }
        return [
            .wrist: point(wrist), .middleMCP: point(middleMCP),
            .indexMCP: point(indexMCP), .pinkyMCP: point(pinkyMCP),
        ]
    }

    /// Palm flat to the lens at 35 cm, fingers up. A right hand held that way
    /// puts its thumb at image right in the unmirrored sensor frame.
    private var rightPalmOn: [HandLandmarkName: MetricPoint3D] {
        landmarks(
            wrist: (0, 40, 350), middleMCP: (0, -40, 350),
            indexMCP: (40, -30, 350), pinkyMCP: (-40, -30, 350)
        )
    }

    /// Same hand rotated until the thumb side faces the lens: the index MCP is
    /// now nearer the camera than the pinky MCP, so the radial axis has turned
    /// toward negative z.
    private var rightThumbSideOn: [HandLandmarkName: MetricPoint3D] {
        landmarks(
            wrist: (0, 40, 350), middleMCP: (0, -40, 350),
            indexMCP: (0, -30, 310), pinkyMCP: (0, -30, 390)
        )
    }

    func testPalmOnMeasuresAsThePalmView() throws {
        let facing = try XCTUnwrap(ScannerAdapterGeometry.handFacing(
            measured: rightPalmOn, handedness: .right
        ))
        XCTAssertEqual(facing.palm, 1, accuracy: 0.0001)
        XCTAssertEqual(facing.thumb, 0, accuracy: 0.0001)
        XCTAssertEqual(ScannerAdapterGeometry.classifyView(facing), .palm)
    }

    /// The sign that stalled the device: turning the thumb toward the lens has
    /// to read positive.
    func testThumbSideOnMeasuresAsAPositiveThumbFacing() throws {
        let facing = try XCTUnwrap(ScannerAdapterGeometry.handFacing(
            measured: rightThumbSideOn, handedness: .right
        ))
        XCTAssertEqual(facing.thumb, 1, accuracy: 0.0001)
        XCTAssertEqual(ScannerAdapterGeometry.classifyView(facing), .thumbSide)
    }

    func testAnObliqueThumbSideIsAcceptedAndAnEdgeOnOneIsNot() throws {
        // Halfway between palm-on and thumb-side-on: the radial axis is 45° to
        // the lens, which is the pose the instructions ask for.
        let oblique = try XCTUnwrap(ScannerAdapterGeometry.handFacing(
            measured: landmarks(
                wrist: (0, 40, 350), middleMCP: (0, -40, 350),
                indexMCP: (28, -30, 322), pinkyMCP: (-28, -30, 378)
            ), handedness: .right
        ))
        XCTAssertEqual(oblique.thumb, 0.7071, accuracy: 0.01)
        XCTAssertTrue(ScannerAdapterGeometry.matchesView(oblique, requested: .thumbSide))
        XCTAssertFalse(ScannerAdapterGeometry.matchesView(
            try XCTUnwrap(ScannerAdapterGeometry.handFacing(
                measured: rightThumbSideOn, handedness: .right
            )), requested: .thumbSide
        ))
    }

    /// A left hand mirrors the radial axis, so the same physical gesture has to
    /// produce the same facing numbers.
    func testTheLeftHandMirrorProducesTheSameFacing() throws {
        let right = try XCTUnwrap(ScannerAdapterGeometry.handFacing(
            measured: rightPalmOn, handedness: .right
        ))
        let left = try XCTUnwrap(ScannerAdapterGeometry.handFacing(
            measured: landmarks(
                wrist: (0, 40, 350), middleMCP: (0, -40, 350),
                indexMCP: (-40, -30, 350), pinkyMCP: (40, -30, 350)
            ), handedness: .left
        ))
        XCTAssertEqual(left.palm, right.palm, accuracy: 0.0001)
        XCTAssertEqual(left.thumb, right.thumb, accuracy: 0.0001)
    }

    func testOrientationNeedsAllFourPalmAnchors() {
        for missing in [HandLandmarkName.wrist, .middleMCP, .indexMCP, .pinkyMCP] {
            var partial = rightPalmOn
            partial.removeValue(forKey: missing)
            XCTAssertNil(
                ScannerAdapterGeometry.handFacing(measured: partial, handedness: .right),
                "\(missing) is required to resolve orientation"
            )
        }
    }
}
