import XCTest
@testable import GripItScannerCore

final class MeasurementStabilityStatusTests: XCTestCase {
    func testSettlingAndMovementHaveDifferentInstructions() {
        var gate = MeasurementStabilityGate()
        let steady = fixtureObservation(view: .palm).landmarks
        XCTAssertFalse(gate.accept(steady))
        XCTAssertEqual(gate.status, .settling)
        _ = gate.accept(steady)
        XCTAssertTrue(gate.accept(steady))
        XCTAssertEqual(gate.status, .ready)
        XCTAssertFalse(gate.accept(fixtureObservation(view: .palm, offset: (20, 0, 0)).landmarks))
        XCTAssertEqual(gate.status, .moving)
    }

    func testCollapsedSideFingerReportsOverlappingRatherThanMovement() {
        var gate = MeasurementStabilityGate()
        var hand = fixtureObservation(view: .thumbSide).landmarks
        let joint = hand[.indexPIP]!
        hand[.indexDIP] = NamedLandmark(name: .indexDIP, point: joint.point, confidence: 0.95)
        _ = gate.accept(hand)
        XCTAssertFalse(gate.accept(hand))
        XCTAssertEqual(gate.status, .overlappingFingers)
    }
}
