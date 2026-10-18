import XCTest
@testable import GripItScannerCore

/// Builds the two hand axes the facing calculation needs, for a hand placed at a
/// known pose in front of the camera.
///
/// Analysis image frame: x right, y down, z away from the camera.
/// Start from "palm at the camera, fingertips up". For a right hand held that way
/// the thumb sits on the person's left, which the unmirrored front sensor sees at
/// image right, so the radial axis starts at +x. A left hand mirrors it.
///
/// `turnDegrees` rotates about the image vertical and brings the thumb side toward
/// the camera. `rollDegrees` rotates about the camera's optical axis: it tilts the
/// hand within the image and cannot change which face the camera sees.
private func handAxes(
    turnDegrees: Double, rollDegrees: Double, pitchDegrees: Double = 0,
    handedness: Handedness
) -> (radial: Vector3D, distal: Vector3D) {
    func rotateAboutY(_ v: Vector3D, _ degrees: Double) -> Vector3D {
        let r = degrees * .pi / 180
        return Vector3D(x: v.x * cos(r) - v.z * sin(r), y: v.y, z: v.x * sin(r) + v.z * cos(r))
    }
    func rotateAboutX(_ v: Vector3D, _ degrees: Double) -> Vector3D {
        let r = degrees * .pi / 180
        return Vector3D(x: v.x, y: v.y * cos(r) - v.z * sin(r), z: v.y * sin(r) + v.z * cos(r))
    }
    func rotateAboutZ(_ v: Vector3D, _ degrees: Double) -> Vector3D {
        let r = degrees * .pi / 180
        return Vector3D(x: v.x * cos(r) - v.y * sin(r), y: v.x * sin(r) + v.y * cos(r), z: v.z)
    }
    // The radial axis starts at +x for a right hand and -x for a left one, so the
    // turn that carries it toward the camera reverses with it. A positive turn
    // always means "thumb side toward the camera" for either hand.
    let radialSign = handedness == .right ? 1.0 : -1.0
    func place(_ v: Vector3D) -> Vector3D {
        rotateAboutZ(
            rotateAboutX(rotateAboutY(v, -turnDegrees * radialSign), pitchDegrees),
            rollDegrees
        )
    }
    return (
        place(Vector3D(x: radialSign, y: 0, z: 0)),
        place(Vector3D(x: 0, y: -1, z: 0))
    )
}

private func facing(
    turnDegrees: Double, rollDegrees: Double = 0, pitchDegrees: Double = 0,
    handedness: Handedness = .right
) throws -> HandFacing {
    let axes = handAxes(
        turnDegrees: turnDegrees, rollDegrees: rollDegrees,
        pitchDegrees: pitchDegrees, handedness: handedness
    )
    return try XCTUnwrap(ScannerAdapterGeometry.handFacing(
        radial: axes.radial, distal: axes.distal, handedness: handedness
    ))
}

final class HandFacingTests: XCTestCase {
    func testPalmAtTheCameraKeepsTheShippedSignConvention() throws {
        for hand in [Handedness.left, .right] {
            let palm = try facing(turnDegrees: 0, handedness: hand)
            XCTAssertEqual(palm.palm, 1, accuracy: 0.0001)
            XCTAssertEqual(palm.thumb, 0, accuracy: 0.0001)
            XCTAssertEqual(palm.fingers, 0, accuracy: 0.0001)
            XCTAssertEqual(ScannerAdapterGeometry.classifyView(palm), .palm)

            let back = try facing(turnDegrees: 180, handedness: hand)
            XCTAssertEqual(back.palm, -1, accuracy: 0.0001)
            XCTAssertEqual(ScannerAdapterGeometry.classifyView(back), .back)
        }
    }

    /// The regression that stalled real scans at the thumb-side step. Rolling the
    /// hand inside the image plane never changes which face of the hand the camera
    /// sees, so the requested-view decision must not move at all.
    func testRollingTheHandInTheImagePlaneNeverChangesTheDecision() throws {
        for hand in [Handedness.left, .right] {
            for requested in [ScanView.thumbSide, .pinkySide] {
                let turn = requested == .thumbSide ? 55.0 : -55.0
                let reference = try facing(turnDegrees: turn, handedness: hand)
                XCTAssertTrue(
                    ScannerAdapterGeometry.matchesView(reference, requested: requested),
                    "\(hand) \(requested) must match with no roll"
                )
                for roll in stride(from: -180.0, through: 180.0, by: 15) {
                    let rolled = try facing(
                        turnDegrees: turn, rollDegrees: roll, handedness: hand
                    )
                    XCTAssertEqual(rolled.palm, reference.palm, accuracy: 0.0001)
                    XCTAssertEqual(rolled.thumb, reference.thumb, accuracy: 0.0001)
                    XCTAssertEqual(rolled.fingers, reference.fingers, accuracy: 0.0001)
                    XCTAssertTrue(
                        ScannerAdapterGeometry.matchesView(rolled, requested: requested),
                        "\(hand) \(requested) rejected at roll \(roll)°"
                    )
                    XCTAssertEqual(ScannerAdapterGeometry.classifyView(rolled), requested)
                }
            }
        }
    }

    /// A landscape analysis buffer rolls every landmark by a quarter turn. That
    /// alone used to make the side views unreachable while palm and back still
    /// passed, which is exactly how the device failure presented.
    func testAQuarterTurnAnalysisBufferStillReachesEverySideView() throws {
        for hand in [Handedness.left, .right] {
            for roll in [90.0, -90.0] {
                XCTAssertTrue(ScannerAdapterGeometry.matchesView(
                    try facing(turnDegrees: 55, rollDegrees: roll, handedness: hand),
                    requested: .thumbSide
                ))
                XCTAssertTrue(ScannerAdapterGeometry.matchesView(
                    try facing(turnDegrees: -55, rollDegrees: roll, handedness: hand),
                    requested: .pinkySide
                ))
                XCTAssertTrue(ScannerAdapterGeometry.matchesView(
                    try facing(turnDegrees: 0, rollDegrees: roll, handedness: hand),
                    requested: .palm
                ))
            }
        }
    }

    func testFullyEdgeOnSidesAreStillRejected() throws {
        for hand in [Handedness.left, .right] {
            let edgeOn = try facing(turnDegrees: 90, handedness: hand)
            XCTAssertEqual(edgeOn.thumb, 1, accuracy: 0.0001)
            XCTAssertFalse(ScannerAdapterGeometry.matchesView(edgeOn, requested: .thumbSide))
        }
    }

    func testTheSideWindowSpansAUsableRangeOfTurnAngles() throws {
        XCTAssertFalse(ScannerAdapterGeometry.matchesView(
            try facing(turnDegrees: 20), requested: .thumbSide
        ))
        for turn in stride(from: 30.0, through: 75.0, by: 5) {
            XCTAssertTrue(
                ScannerAdapterGeometry.matchesView(
                    try facing(turnDegrees: turn), requested: .thumbSide
                ),
                "turn \(turn)° should be an acceptable oblique thumb side"
            )
        }
    }

    func testThumbAndPinkySidesStayDistinct() throws {
        let thumb = try facing(turnDegrees: 55)
        let pinky = try facing(turnDegrees: -55)
        XCTAssertTrue(ScannerAdapterGeometry.matchesView(thumb, requested: .thumbSide))
        XCTAssertFalse(ScannerAdapterGeometry.matchesView(thumb, requested: .pinkySide))
        XCTAssertTrue(ScannerAdapterGeometry.matchesView(pinky, requested: .pinkySide))
        XCTAssertFalse(ScannerAdapterGeometry.matchesView(pinky, requested: .thumbSide))
    }

    /// Fingertips aimed down the lens foreshorten every finger, so no view may be
    /// accepted from that pose however well the palm or thumb lines up.
    func testFingertipsAimedAtTheCameraAreRejectedForEveryView() throws {
        let pointing = try facing(turnDegrees: 0, pitchDegrees: 75)
        XCTAssertGreaterThan(pointing.fingers, 0.9)
        for requested in ScanView.requiredOrder {
            XCTAssertFalse(ScannerAdapterGeometry.matchesView(pointing, requested: requested))
        }
    }

    func testDegenerateAxesProduceNoFacing() {
        XCTAssertNil(ScannerAdapterGeometry.handFacing(
            radial: Vector3D(x: 0, y: 0, z: 0),
            distal: Vector3D(x: 0, y: -1, z: 0), handedness: .right
        ))
        XCTAssertNil(ScannerAdapterGeometry.handFacing(
            radial: Vector3D(x: 1, y: 0, z: 0),
            distal: Vector3D(x: 2, y: 0, z: 0), handedness: .right
        ))
        XCTAssertNil(ScannerAdapterGeometry.handFacing(
            radial: Vector3D(x: .nan, y: 0, z: 0),
            distal: Vector3D(x: 0, y: -1, z: 0), handedness: .right
        ))
    }
}
