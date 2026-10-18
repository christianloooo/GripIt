import Foundation
import XCTest
@testable import GripItScannerCore

final class ContractCompatibilityTests: XCTestCase {
    func testLibraryProvidesSimulatorProfile() throws {
        XCTAssertEqual(try SampleHandProfiles.averageRight().profileId, "sample-average-right")
    }

    func testSharedFixtureDecodesAndRoundTrips() throws {
        let profile = try SampleHandProfiles.averageRight()

        XCTAssertEqual(profile.schemaVersion, "1.0.0")
        XCTAssertEqual(profile.profileId, "sample-average-right")
        XCTAssertEqual(profile.measurements.palm.widthMm, 82)
        XCTAssertEqual(try HandProfileCodec.decode(HandProfileCodec.encode(profile)), profile)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: HandProfileCodec.encode(profile)) as? [String: Any]
        )
        let measurements = try XCTUnwrap(object["measurements"] as? [String: Any])
        let palm = try XCTUnwrap(measurements["palm"] as? [String: Any])
        XCTAssertTrue(palm["thicknessMm"] is NSNull)
        let fingers = try XCTUnwrap(measurements["fingers"] as? [String: Any])
        for name in ["index", "middle", "ring", "pinky", "thumb"] {
            let finger = try XCTUnwrap(fingers[name] as? [String: Any])
            XCTAssertTrue(finger["diameterMm"] is NSNull)
        }
    }

    func testUnsupportedMajorVersionIsRejected() throws {
        let data = Data(#"{"schemaVersion":"2.0.0"}"#.utf8)

        XCTAssertThrowsError(try HandProfileCodec.decode(data)) { error in
            XCTAssertEqual(error as? HandProfileCodingError, .unsupportedMajorVersion(2))
        }
    }

    func testUnknownAdditiveFieldsAreIgnored() throws {
        let data = Data(
            #"{"schemaVersion":"1.9.0","profileId":"p","createdAt":"2026-10-17T00:00:00Z","handedness":"right","units":"millimeters","coordinateSystem":"gripit-hand-v1","measurements":{"palm":{"widthMm":82,"lengthMm":72,"thicknessMm":null},"fingers":{"index":{"segmentsMm":[1,2,3],"diameterMm":null},"middle":{"segmentsMm":[1,2,3],"diameterMm":null},"ring":{"segmentsMm":[1,2,3],"diameterMm":null},"pinky":{"segmentsMm":[1,2,3],"diameterMm":null},"thumb":{"segmentsMm":[1,2,3],"diameterMm":null}}},"landmarks":{},"capture":{"method":"sample","coverage":{"requiredViews":[],"capturedViews":[],"fraction":0},"calibration":{"method":"none"},"confidence":1},"extensions":{},"futureField":true}"#.utf8
        )

        XCTAssertEqual(try HandProfileCodec.decode(data).schemaVersion, "1.9.0")
    }
}
