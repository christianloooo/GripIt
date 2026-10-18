import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import UIKit

struct SynchronizedCaptureFrame {
    let pixelBuffer: CVPixelBuffer
    let depthData: AVDepthData
    let timestamp: CMTime

    /// The capture outputs remain in their native, unmirrored sensor orientation.
    /// Passing `.left` to MediaPipe rotates a front-camera buffer upright for a
    /// portrait user without changing the pixel or depth buffers themselves.
    let imageOrientation: UIImage.Orientation
}

final class TrueDepthCaptureService: NSObject {
    let session = AVCaptureSession()

    /// Called on the serial capture queue. The frame is valid only for immediate processing.
    var onFrame: (@Sendable (SynchronizedCaptureFrame) -> Void)? {
        get { callbackLock.withLock { frameHandler } }
        set { callbackLock.withLock { frameHandler = newValue } }
    }

    /// Called on the serial capture queue.
    var onError: (@Sendable (String) -> Void)? {
        get { callbackLock.withLock { errorHandler } }
        set { callbackLock.withLock { errorHandler = newValue } }
    }

    private let callbackLock = NSLock()
    private var frameHandler: (@Sendable (SynchronizedCaptureFrame) -> Void)?
    private var errorHandler: (@Sendable (String) -> Void)?

    private let captureQueue = DispatchQueue(
        label: "com.gripit.truedepth.capture",
        qos: .userInitiated
    )
    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?

    private let deliveryInterval = CMTime(value: 1, timescale: 8)
    private let maximumAutomaticRestartAttempts = 1
    private var lastDeliveredTimestamp = CMTime.invalid
    private var isConfigured = false
    private var wantsToRun = false
    private var automaticRestartAttempts = 0
    private var lastReportedError: String?
    private var timestampMismatchCount = 0

    override init() {
        super.init()
        addSessionObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        captureQueue.async { [weak self] in
            guard let self else { return }
            wantsToRun = true
            automaticRestartAttempts = 0
            lastReportedError = nil
            timestampMismatchCount = 0
            startAfterAuthorization()
        }
    }

    func stop() {
        captureQueue.async { [weak self] in
            guard let self else { return }
            wantsToRun = false
            automaticRestartAttempts = 0
            lastDeliveredTimestamp = .invalid
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func startAfterAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startConfiguredSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                captureQueue.async {
                    guard self.wantsToRun else { return }
                    if granted {
                        self.startConfiguredSession()
                    } else {
                        self.reportError("Camera access was denied.")
                    }
                }
            }
        case .denied:
            reportError("Camera access is denied. Enable it in Settings to scan.")
        case .restricted:
            reportError("Camera access is restricted on this device.")
        @unknown default:
            reportError("Camera authorization is unavailable.")
        }
    }

    private func startConfiguredSession() {
        guard wantsToRun else { return }

        do {
            if !isConfigured {
                try configureSession()
                isConfigured = true
            }
            guard !session.isRunning else { return }
            session.startRunning()
            if !session.isRunning {
                reportError("The TrueDepth capture session did not start.")
            }
        } catch {
            reportError(error.localizedDescription)
        }
    }

    private func configureSession() throws {
        guard let device = AVCaptureDevice.default(
            .builtInTrueDepthCamera,
            for: .video,
            position: .front
        ) else {
            throw CaptureServiceError.trueDepthUnavailable
        }

        let formats = try Self.preferredFormats(for: device)
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        session.sessionPreset = .inputPriority

        do {
            guard session.canAddInput(input) else {
                throw CaptureServiceError.cannotAddCameraInput
            }
            session.addInput(input)

            try device.lockForConfiguration()
            device.activeFormat = formats.video
            device.activeDepthDataFormat = formats.depth
            if formats.video.videoSupportedFrameRateRanges.contains(where: {
                $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
            }) {
                let frameDuration = CMTime(value: 1, timescale: 30)
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration
            }
            device.unlockForConfiguration()

            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            ]
            guard session.canAddOutput(videoOutput) else {
                throw CaptureServiceError.cannotAddVideoOutput
            }
            session.addOutput(videoOutput)

            depthOutput.alwaysDiscardsLateDepthData = true
            depthOutput.isFilteringEnabled = false
            guard session.canAddOutput(depthOutput) else {
                throw CaptureServiceError.cannotAddDepthOutput
            }
            session.addOutput(depthOutput)

            try Self.configureNativeUnmirroredConnection(
                videoOutput.connection(with: .video),
                name: "video"
            )
            try Self.configureNativeUnmirroredConnection(
                depthOutput.connection(with: .depthData),
                name: "depth"
            )

            session.commitConfiguration()
        } catch {
            if session.outputs.contains(videoOutput) {
                session.removeOutput(videoOutput)
            }
            if session.outputs.contains(depthOutput) {
                session.removeOutput(depthOutput)
            }
            if session.inputs.contains(input) {
                session.removeInput(input)
            }
            session.commitConfiguration()
            throw error
        }

        let synchronizer = AVCaptureDataOutputSynchronizer(
            dataOutputs: [videoOutput, depthOutput]
        )
        synchronizer.setDelegate(self, queue: captureQueue)
        outputSynchronizer = synchronizer
    }

    private static func preferredFormats(
        for device: AVCaptureDevice
    ) throws -> (video: AVCaptureDevice.Format, depth: AVCaptureDevice.Format) {
        let candidates = device.formats.flatMap { videoFormat in
            videoFormat.supportedDepthDataFormats.map { depthFormat in
                FormatCandidate(video: videoFormat, depth: depthFormat)
            }
        }.filter(\.hasMatchingAspectRatio)

        guard let candidate = candidates.sorted(by: FormatCandidate.isPreferred).first else {
            throw CaptureServiceError.compatibleDepthFormatUnavailable
        }
        return (candidate.video, candidate.depth)
    }

    private static func configureNativeUnmirroredConnection(
        _ connection: AVCaptureConnection?,
        name: String
    ) throws {
        guard let connection else {
            throw CaptureServiceError.missingOutputConnection(name)
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        // Do not set videoRotationAngle. RGB and depth stay in the same native
        // sensor orientation so their normalized coordinates remain aligned.
    }

    private func addSessionObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        captureQueue.async { [weak self] in
            guard let self else { return }
            if error?.code == .mediaServicesWereReset {
                attemptAutomaticRestart(after: "Camera media services were reset.")
            } else {
                reportError(error?.localizedDescription ?? "The capture session failed.")
            }
        }
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        captureQueue.async { [weak self] in
            self?.reportError("Camera capture was interrupted. It will resume when available.")
        }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        captureQueue.async { [weak self] in
            self?.attemptAutomaticRestart(after: "Camera capture did not resume.")
        }
    }

    private func attemptAutomaticRestart(after failureMessage: String) {
        guard wantsToRun, !session.isRunning else { return }
        guard automaticRestartAttempts < maximumAutomaticRestartAttempts else {
            reportError(failureMessage)
            return
        }
        automaticRestartAttempts += 1
        session.startRunning()
        if !session.isRunning {
            reportError(failureMessage)
        }
    }

    private func reportError(_ message: String) {
        guard message != lastReportedError else { return }
        lastReportedError = message
        onError?(message)
    }
}

extension TrueDepthCaptureService: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        guard wantsToRun,
              let videoData = synchronizedDataCollection.synchronizedData(
                  for: videoOutput
              ) as? AVCaptureSynchronizedSampleBufferData,
              let depthData = synchronizedDataCollection.synchronizedData(
                  for: depthOutput
              ) as? AVCaptureSynchronizedDepthData,
              !videoData.sampleBufferWasDropped,
              !depthData.depthDataWasDropped
        else {
            return
        }

        let videoTimestamp = CMSampleBufferGetPresentationTimeStamp(videoData.sampleBuffer)
        // The synchronizer pairs nearest capture times; tiny sensor timing offsets
        // are expected. Never combine samples separated by more than one frame.
        let timestampDelta = abs(CMTimeGetSeconds(CMTimeSubtract(videoTimestamp, depthData.timestamp)))
        guard timestampDelta.isFinite, timestampDelta <= 1.0 / 30.0 else {
            timestampMismatchCount += 1
            if timestampMismatchCount >= 30 {
                reportError("Color and depth could not synchronize. Restart the scan.")
            }
            return
        }
        timestampMismatchCount = 0

        if lastDeliveredTimestamp.isValid {
            let elapsed = CMTimeSubtract(videoTimestamp, lastDeliveredTimestamp)
            guard CMTimeCompare(elapsed, deliveryInterval) >= 0 else { return }
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(videoData.sampleBuffer) else {
            reportError("The synchronized RGB sample has no pixel buffer.")
            return
        }

        let capturedDepth = depthData.depthData
        let floatDepth: AVDepthData
        if capturedDepth.depthDataType == kCVPixelFormatType_DepthFloat32 {
            floatDepth = capturedDepth
        } else if capturedDepth.availableDepthDataTypes.contains(kCVPixelFormatType_DepthFloat32) {
            floatDepth = capturedDepth.converting(
                toDepthDataType: kCVPixelFormatType_DepthFloat32
            )
        } else {
            reportError("TrueDepth data cannot be converted to metric Float32 depth.")
            return
        }

        guard let calibration = floatDepth.cameraCalibrationData else {
            reportError("The synchronized depth frame has no camera calibration data.")
            return
        }

        let depthMap = floatDepth.depthDataMap
        let videoWidth = CVPixelBufferGetWidth(pixelBuffer)
        let videoHeight = CVPixelBufferGetHeight(pixelBuffer)
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let referenceSize = calibration.intrinsicMatrixReferenceDimensions
        guard Self.hasMatchingAspectRatio(
            width: videoWidth,
            height: videoHeight,
            referenceSize: referenceSize
        ), Self.hasMatchingAspectRatio(
            width: depthWidth,
            height: depthHeight,
            referenceSize: referenceSize
        ) else {
            reportError(
                "RGB, depth, and calibration reference dimensions have different aspect ratios."
            )
            return
        }

        lastDeliveredTimestamp = videoTimestamp
        automaticRestartAttempts = 0
        lastReportedError = nil
        onFrame?(
            SynchronizedCaptureFrame(
                pixelBuffer: pixelBuffer,
                depthData: floatDepth,
                timestamp: videoTimestamp,
                imageOrientation: .left
            )
        )
    }

    private static func hasMatchingAspectRatio(
        width: Int,
        height: Int,
        referenceSize: CGSize
    ) -> Bool {
        guard width > 0,
              height > 0,
              referenceSize.width > 0,
              referenceSize.height > 0
        else {
            return false
        }
        let imageRatio = Double(width) / Double(height)
        let referenceRatio = Double(referenceSize.width / referenceSize.height)
        return abs(imageRatio - referenceRatio) < 0.001
    }
}

private struct FormatCandidate {
    let video: AVCaptureDevice.Format
    let depth: AVCaptureDevice.Format

    private var depthSubtype: OSType {
        CMFormatDescriptionGetMediaSubType(depth.formatDescription)
    }

    private var depthDimensions: CMVideoDimensions {
        CMVideoFormatDescriptionGetDimensions(depth.formatDescription)
    }

    private var videoDimensions: CMVideoDimensions {
        CMVideoFormatDescriptionGetDimensions(video.formatDescription)
    }

    private var depthTypeRank: Int {
        switch depthSubtype {
        case kCVPixelFormatType_DepthFloat32: 4
        case kCVPixelFormatType_DepthFloat16: 3
        case kCVPixelFormatType_DisparityFloat32: 2
        case kCVPixelFormatType_DisparityFloat16: 1
        default: 0
        }
    }

    private var depthPixelCount: Int64 {
        Int64(depthDimensions.width) * Int64(depthDimensions.height)
    }

    private var videoPixelCount: Int64 {
        Int64(videoDimensions.width) * Int64(videoDimensions.height)
    }

    var hasMatchingAspectRatio: Bool {
        guard videoDimensions.width > 0,
              videoDimensions.height > 0,
              depthDimensions.width > 0,
              depthDimensions.height > 0
        else {
            return false
        }
        return Int64(videoDimensions.width) * Int64(depthDimensions.height)
            == Int64(videoDimensions.height) * Int64(depthDimensions.width)
    }

    static func isPreferred(_ left: FormatCandidate, _ right: FormatCandidate) -> Bool {
        if left.depthTypeRank != right.depthTypeRank {
            return left.depthTypeRank > right.depthTypeRank
        }
        if left.depthPixelCount != right.depthPixelCount {
            return left.depthPixelCount > right.depthPixelCount
        }

        // MediaPipe downsamples internally. For equal depth quality, prefer the
        // smaller compatible RGB stream to reduce CPU and memory bandwidth.
        return left.videoPixelCount < right.videoPixelCount
    }
}

private enum CaptureServiceError: LocalizedError {
    case trueDepthUnavailable
    case compatibleDepthFormatUnavailable
    case cannotAddCameraInput
    case cannotAddVideoOutput
    case cannotAddDepthOutput
    case missingOutputConnection(String)

    var errorDescription: String? {
        switch self {
        case .trueDepthUnavailable:
            "This device has no available front TrueDepth camera."
        case .compatibleDepthFormatUnavailable:
            "The TrueDepth camera has no video format with compatible depth data."
        case .cannotAddCameraInput:
            "The TrueDepth camera cannot be added to the capture session."
        case .cannotAddVideoOutput:
            "The RGB output cannot be added to the capture session."
        case .cannotAddDepthOutput:
            "The depth output cannot be added to the capture session."
        case let .missingOutputConnection(name):
            "The capture session did not create its \(name) connection."
        }
    }
}
