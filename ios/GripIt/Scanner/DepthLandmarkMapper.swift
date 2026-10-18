import AVFoundation
import GripItScannerCore
import UIKit

struct DepthMappingResult {
    let landmarks: [HandLandmarkName: NamedLandmark]
    let sensorPoints: [CGPoint]
    let distanceMeters: Double?
}

enum DepthLandmarkMapper {
    static func map(
        modelPoints: [CGPoint], depth: AVDepthData, orientation: UIImage.Orientation,
        confidence: Double, videoWidth: Int, videoHeight: Int
    ) throws -> DepthMappingResult {
        guard modelPoints.count == 21, let calibration = depth.cameraCalibrationData else {
            throw MappingError.missingCalibration
        }
        let converted = depth.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = converted.depthDataMap
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        let matrix = calibration.intrinsicMatrix
        let reference = calibration.intrinsicMatrixReferenceDimensions
        let referenceAspect = Double(reference.width / reference.height)
        guard videoWidth > 0, videoHeight > 0,
              abs(Double(videoWidth) / Double(videoHeight) - referenceAspect) < 0.01,
              abs(Double(width) / Double(height) - referenceAspect) < 0.01 else {
            throw MappingError.incompatibleGeometry
        }
        let distortionTable: [Double]? = calibration.lensDistortionLookupTable.map { data in
            data.withUnsafeBytes { bytes in
                (0 ..< data.count / MemoryLayout<Float>.size).map {
                    Double(bytes.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Float>.size, as: Float.self))
                }
            }
        }
        guard let intrinsics = ScannerAdapterGeometry.scaledIntrinsics(
            fx: Double(matrix.columns.0.x), fy: Double(matrix.columns.1.y),
            cx: Double(matrix.columns.2.x), cy: Double(matrix.columns.2.y),
            referenceWidth: Double(reference.width), referenceHeight: Double(reference.height),
            depthWidth: width, depthHeight: height
        ) else { throw MappingError.missingCalibration }
        let rotation: SensorImageRotation
        switch orientation {
        case .up: rotation = .up
        case .down: rotation = .down
        case .left: rotation = .left
        case .right: rotation = .right
        default: throw MappingError.mirroredAnalysis
        }
        let points = modelPoints.map { point -> CGPoint in
            let p = rotation.sensorPoint(fromModel: PixelPoint(x: Double(point.x), y: Double(point.y)))
            return CGPoint(x: p.x, y: p.y)
        }
        guard CVPixelBufferLockBaseAddress(map, .readOnly) == kCVReturnSuccess else {
            throw MappingError.missingDepth
        }
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { throw MappingError.missingDepth }
        let stride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float32>.stride
        let values = base.assumingMemoryBound(to: Float32.self)
        var landmarks: [HandLandmarkName: NamedLandmark] = [:]
        var distances: [Double] = []
        for (name, p) in zip(HandLandmarkName.allCases, points) {
            guard p.x.isFinite, p.y.isFinite, (0...1).contains(p.x), (0...1).contains(p.y) else { continue }
            let x = min(width - 1, Int(p.x * CGFloat(width)))
            let y = min(height - 1, Int(p.y * CGFloat(height)))
            var neighborhood: [Double] = []
            for row in max(0, y - 1)...min(height - 1, y + 1) {
                for column in max(0, x - 1)...min(width - 1, x + 1) {
                    neighborhood.append(Double(values[row * stride + column]))
                }
            }
            guard let meters = ScannerAdapterGeometry.medianValidDepth(neighborhood) else { continue }
            // Reject depth discontinuities instead of taking background depth at a finger edge.
            let valid = neighborhood.filter { $0.isFinite && (0.12...1.2).contains($0) }
            guard valid.count >= 5,
                  valid.filter({ abs($0 - meters) <= 0.015 }).count >= 5 else { continue }
            var projectionPixel = PixelPoint(x: Double(p.x) * Double(width), y: Double(p.y) * Double(height))
            if let distortionTable {
                let center = calibration.lensDistortionCenter
                guard let rectified = ScannerAdapterGeometry.rectifiedPixel(
                    projectionPixel,
                    center: PixelPoint(x: Double(center.x) * Double(width) / Double(reference.width),
                                       y: Double(center.y) * Double(height) / Double(reference.height)),
                    width: Double(width), height: Double(height), lookupTable: distortionTable
                ) else { continue }
                projectionPixel = rectified
            }
            let metric = try DepthProjector.project(pixel: projectionPixel, depthMeters: meters, intrinsics: intrinsics)
            landmarks[name] = NamedLandmark(name: name, point: metric, confidence: confidence)
            distances.append(meters)
        }
        return DepthMappingResult(
            landmarks: landmarks, sensorPoints: points,
            distanceMeters: ScannerAdapterGeometry.medianValidDepth(distances)
        )
    }

    enum MappingError: LocalizedError {
        case missingCalibration, missingDepth, mirroredAnalysis, incompatibleGeometry
        var errorDescription: String? {
            switch self {
            case .missingCalibration: "Camera calibration is unavailable. Try restarting the scan."
            case .missingDepth: "Depth data is unavailable. Change the hand angle slightly."
            case .mirroredAnalysis: "Unsupported camera orientation. Hold the phone upright."
            case .incompatibleGeometry: "Color and depth formats do not align. Restart using a compatible capture format."
            }
        }
    }
}
