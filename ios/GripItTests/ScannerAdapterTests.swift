import XCTest
import CoreVideo
import UIKit
import GripItScannerCore
@testable import GripIt

final class ScannerAdapterTests: XCTestCase {
    func testRGBRotationMatchesSensorCoordinateInverse() throws {
        var source: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 2, 1, kCVPixelFormatType_32BGRA,
                                          attributes, &source), kCVReturnSuccess)
        let input = try XCTUnwrap(source)
        CVPixelBufferLockBaseAddress(input, [])
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(input)).assumingMemoryBound(to: UInt8.self)
        // Red on the left and green on the right in the raw sensor image.
        let colors: [UInt8] = [0, 0, 255, 255, 0, 255, 0, 255]
        for (offset, value) in colors.enumerated() { bytes[offset] = value }
        CVPixelBufferUnlockBaseAddress(input, [])
        let service = try HandLandmarkerService()
        let upright = try service.prepareUpright(input, orientation: .left)
        XCTAssertEqual(CVPixelBufferGetWidth(upright), 1)
        XCTAssertEqual(CVPixelBufferGetHeight(upright), 2)
        CVPixelBufferLockBaseAddress(upright, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(upright, .readOnly) }
        let result = try XCTUnwrap(CVPixelBufferGetBaseAddress(upright)).assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(upright)
        XCTAssertGreaterThan(result[1], 240, "The model's top pixel maps to the sensor's right pixel")
        XCTAssertGreaterThan(result[row + 2], 240, "The model's bottom pixel maps to the sensor's left pixel")
    }

    func testPortraitPointsMapToNativeSensorCorners() {
        let topLeft = SensorImageRotation.left.sensorPoint(fromModel: PixelPoint(x: 0, y: 0))
        XCTAssertEqual(topLeft.x, 1)
        XCTAssertEqual(topLeft.y, 0)
        let bottomRight = SensorImageRotation.left.sensorPoint(fromModel: PixelPoint(x: 1, y: 1))
        XCTAssertEqual(bottomRight.x, 0)
        XCTAssertEqual(bottomRight.y, 1)
    }

    func testCameraReportedQuarterTurnsMatchPhysicalRGBPixels() throws {
        var source: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 2, 1, kCVPixelFormatType_32BGRA,
                                          attributes, &source), kCVReturnSuccess)
        let input = try XCTUnwrap(source)
        CVPixelBufferLockBaseAddress(input, [])
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(input)).assumingMemoryBound(to: UInt8.self)
        let colors: [UInt8] = [0, 0, 255, 255, 0, 255, 0, 255]
        for (offset, value) in colors.enumerated() {
            bytes[offset] = value
        }
        CVPixelBufferUnlockBaseAddress(input, [])
        let service = try HandLandmarkerService()
        let cases: [(UIImage.Orientation, Int, Int, Int, Int)] = [
            (.up, 2, 1, 2, 1), (.right, 1, 2, 2, 1),
            (.down, 2, 1, 1, 2), (.left, 1, 2, 1, 2)
        ]
        for (orientation, width, height, firstChannel, lastChannel) in cases {
            let output = try service.prepareUpright(input, orientation: orientation)
            XCTAssertEqual(CVPixelBufferGetWidth(output), width)
            XCTAssertEqual(CVPixelBufferGetHeight(output), height)
            CVPixelBufferLockBaseAddress(output, .readOnly)
            let result = try XCTUnwrap(CVPixelBufferGetBaseAddress(output)).assumingMemoryBound(to: UInt8.self)
            let lastOffset = (height - 1) * CVPixelBufferGetBytesPerRow(output) + (width - 1) * 4
            XCTAssertGreaterThan(result[firstChannel], 240)
            XCTAssertGreaterThan(result[lastOffset + lastChannel], 240)
            CVPixelBufferUnlockBaseAddress(output, .readOnly)
        }
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
    func testSampleFlowProducesExportWithoutStartingCamera() async throws {
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
