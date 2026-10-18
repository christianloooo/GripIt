import CoreGraphics
import CoreVideo
import Foundation
import MediaPipeTasksVision
import UIKit

struct HandDetection {
    /// Normalized coordinates in the orientation-corrected MediaPipe model image.
    let points: [CGPoint]
    let worldPoints: [SIMD3<Double>]
    let label: String
    let confidence: Double
    let handCount: Int
}

final class HandLandmarkerService {
    private let handLandmarker: HandLandmarker
    private let inferenceLock = NSLock()
    private var lastTimestampMilliseconds = -1

    init() throws {
        guard let modelPath = Bundle.main.path(
            forResource: "hand_landmarker",
            ofType: "task"
        ) else {
            throw HandLandmarkerServiceError.missingModel
        }

        let options = HandLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.baseOptions.delegate = .CPU
        options.runningMode = .video
        options.numHands = 2
        options.minHandDetectionConfidence = 0.7
        options.minHandPresenceConfidence = 0.7
        options.minTrackingConfidence = 0.7
        handLandmarker = try HandLandmarker(options: options)
    }

    /// Runs synchronous video-mode inference. Callers should pass frames from one
    /// serial queue. The lock also prevents accidental concurrent task access.
    ///
    /// `points` are normalized in the orientation-corrected model image. For the
    /// native front-camera portrait input (`orientation == .left`), map a model
    /// point `(x, y)` back into the native, unmirrored sensor/depth coordinates as
    /// `(1 - y, x)`. Apply that inverse mapping before depth lookup or passing the
    /// point to a preview layer's coordinate conversion API.
    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: UIImage.Orientation,
        timestampMilliseconds: Int
    ) throws -> HandDetection? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            throw HandLandmarkerServiceError.unsupportedPixelFormat
        }
        guard !orientation.isMirrored else {
            throw HandLandmarkerServiceError.mirroredOrientationUnsupported
        }
        guard timestampMilliseconds >= 0 else {
            throw HandLandmarkerServiceError.invalidTimestamp(timestampMilliseconds)
        }

        inferenceLock.lock()
        defer { inferenceLock.unlock() }

        guard timestampMilliseconds > lastTimestampMilliseconds else {
            throw HandLandmarkerServiceError.nonMonotonicTimestamp(
                previous: lastTimestampMilliseconds,
                current: timestampMilliseconds
            )
        }

        let image = try MPImage(pixelBuffer: pixelBuffer, orientation: orientation)
        let result = try handLandmarker.detect(
            videoFrame: image,
            timestampInMilliseconds: timestampMilliseconds
        )
        lastTimestampMilliseconds = timestampMilliseconds

        let handCount = result.landmarks.count
        guard handCount > 0,
              let normalizedLandmarks = result.landmarks.first,
              let worldLandmarks = result.worldLandmarks.first,
              normalizedLandmarks.count == 21,
              worldLandmarks.count == 21,
              let category = result.handedness.first?.max(by: { $0.score < $1.score })
        else {
            return nil
        }

        return HandDetection(
            points: normalizedLandmarks.map {
                CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))
            },
            worldPoints: worldLandmarks.map {
                SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z))
            },
            label: category.categoryName ?? "Unknown",
            confidence: Double(category.score),
            handCount: handCount
        )
    }
}

private extension UIImage.Orientation {
    var isMirrored: Bool {
        switch self {
        case .upMirrored, .downMirrored, .leftMirrored, .rightMirrored:
            true
        default:
            false
        }
    }
}

private enum HandLandmarkerServiceError: LocalizedError {
    case missingModel
    case unsupportedPixelFormat
    case mirroredOrientationUnsupported
    case invalidTimestamp(Int)
    case nonMonotonicTimestamp(previous: Int, current: Int)

    var errorDescription: String? {
        switch self {
        case .missingModel:
            "The bundled hand_landmarker.task model is missing."
        case .unsupportedPixelFormat:
            "MediaPipe requires a 32BGRA camera pixel buffer."
        case .mirroredOrientationUnsupported:
            "MediaPipe does not support mirrored UIImage orientations."
        case let .invalidTimestamp(timestamp):
            "The MediaPipe timestamp must be nonnegative. Received \(timestamp)."
        case let .nonMonotonicTimestamp(previous, current):
            "MediaPipe timestamps must increase. Received \(current) after \(previous)."
        }
    }
}
