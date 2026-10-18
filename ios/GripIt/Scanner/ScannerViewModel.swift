import AVFoundation
import Combine
import GripItScannerCore
import SwiftUI
import simd

enum ScannerPhase: String { case chooseHand, requestingPermission, scanning, complete, failed }

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var phase: ScannerPhase = .chooseHand
    @Published var selectedHand: Handedness = .right
    @Published var message = "Choose the hand you want to scan."
    @Published var progress = 0.0
    @Published var currentView: ScanView? = .palm
    /// Normalized, unrotated sensor coordinates. The preview layer owns mirroring and cropping.
    @Published var points: [CGPoint] = []
    @Published var sensorSize: CGSize = .zero
    @Published var jointFractions: [HandLandmarkName: Double] = [:]
    @Published var validDepthCount = 0
    @Published var acceptedViewFrames = 0
    @Published var trackingStatus = "Identifying hand"
    @Published var distanceCm: Double?
    @Published var profile: HandProfile?
    @Published var diagnostics = ""
    @Published var exportURL: URL?

    private let capture = TrueDepthCaptureService()
    private var generation = UUID()
    var captureSession: AVCaptureSession { capture.session }

    func start(hand: Handedness) {
        reset()
        selectedHand = hand
        phase = .requestingPermission
        let token = generation
        Task {
            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: granted = true
            case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
            default: granted = false
            }
            guard token == generation else { return }
            guard granted else {
                phase = .failed
                message = "Camera access is off. Enable GripIt in Settings to scan."
                return
            }
            #if targetEnvironment(simulator)
            phase = .failed
            message = "TrueDepth requires an iPhone. Use the sample profile in Simulator."
            #else
            let processor = ScannerFrameProcessor(hand: hand)
            capture.onFrame = { [weak self] frame in
                let update = processor.process(frame)
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token, self.phase == .scanning else { return }
                    self.apply(update)
                }
            }
            capture.onError = { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.message = error
                    self.phase = .failed
                    self.generation = UUID()
                    self.capture.onFrame = nil
                    self.capture.onError = nil
                    self.capture.stop()
                    self.points = []
                }
            }
            phase = .scanning
            message = "Face your palm toward the camera."
            capture.start()
            #endif
        }
    }

    func stop() {
        generation = UUID()
        capture.onFrame = nil
        capture.onError = nil
        capture.stop()
        points = []
        if phase == .scanning || phase == .requestingPermission {
            phase = .chooseHand
            message = "Scan paused. Choose your hand to start again."
        }
    }

    func reset() {
        stop()
        removeExport()
        phase = .chooseHand
        progress = 0
        currentView = .palm
        jointFractions = [:]
        validDepthCount = 0
        acceptedViewFrames = 0
        trackingStatus = "Identifying hand"
        distanceCm = nil
        profile = nil
        diagnostics = ""
        message = "Choose the hand you want to scan."
    }

    func loadSample() {
        reset()
        do {
            profile = try SampleHandProfiles.averageRight()
            phase = .complete
            progress = 1
            currentView = nil
            message = "Sample profile. These measurements are not from your hand."
            diagnostics = "Bundled sample data · camera was not used"
            exportProfile()
        } catch {
            phase = .failed
            message = error.localizedDescription
        }
    }

    func exportProfile() {
        guard let profile else { return }
        do {
            removeExport()
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("gripit-hand-\(profile.profileId).json")
            try HandProfileCodec.encode(profile).write(to: file, options: .atomic)
            exportURL = file
        } catch { message = "Could not export the profile: \(error.localizedDescription)" }
    }

    private func removeExport() {
        if let exportURL { try? FileManager.default.removeItem(at: exportURL) }
        exportURL = nil
    }

    private func apply(_ update: ScannerFrameUpdate) {
        points = update.points
        sensorSize = update.sensorSize
        validDepthCount = update.validDepthCount
        acceptedViewFrames = update.coverage.acceptedFramesInCurrentView
        trackingStatus = update.trackingStatus
        distanceCm = update.distanceMeters.map { $0 * 100 }
        currentView = update.coverage.currentView
        progress = update.coverage.fraction
        jointFractions = update.jointFractions
        message = update.message
        diagnostics = update.diagnostics
        if update.initializationFailed {
            generation = UUID()
            capture.onFrame = nil
            capture.onError = nil
            capture.stop()
            phase = .failed
            return
        }
        if let result = update.profile {
            profile = result
            phase = .complete
            generation = UUID()
            capture.onFrame = nil
            capture.onError = nil
            capture.stop()
            points = []
            exportProfile()
        }
    }
}

private struct ScannerFrameUpdate: Sendable {
    let points: [CGPoint]
    let sensorSize: CGSize
    let validDepthCount: Int
    let distanceMeters: Double?
    let coverage: CoverageSnapshot
    let jointFractions: [HandLandmarkName: Double]
    let message: String
    let diagnostics: String
    let profile: HandProfile?
    let initializationFailed: Bool
    let trackingStatus: String
}

/// All mutable processing state is confined to the capture service's serial queue.
private final class ScannerFrameProcessor: @unchecked Sendable {
    let hand: Handedness
    private var landmarker: HandLandmarkerService?
    private var session = ScannerSession(minimumFramesPerView: 8, minimumConfidence: 0.8)
    private var joints = LandmarkCoverageTracker(minimumSamplesPerLandmark: 8)
    private var lastTimestamp = -1
    private var consecutiveViewFrames = 0
    private var previousView: ScanView?
    private var counts: [ScanView: Int] = [:]
    private var stability = MeasurementStabilityGate()
    private var recentDepth = RecentDepthLandmarks()
    private var identity: HandIdentityTracker

    init(hand: Handedness) {
        self.hand = hand
        identity = HandIdentityTracker(hand: hand)
    }

    func process(_ frame: SynchronizedCaptureFrame) -> ScannerFrameUpdate {
        var points: [CGPoint] = []
        var depthCount = 0
        var distance: Double?
        var result: HandProfile?
        var message = "Show your whole hand with fingers comfortably spread."
        var diagnostics = ""
        var initializationFailed = false
        do {
            if landmarker == nil {
                do { landmarker = try HandLandmarkerService() }
                catch { initializationFailed = true; throw error }
            }
            let timestamp = max(lastTimestamp + 1, Int(CMTimeGetSeconds(frame.timestamp) * 1000))
            lastTimestamp = timestamp
            guard let detection = try landmarker?.detect(
                pixelBuffer: frame.pixelBuffer, orientation: frame.imageOrientation,
                timestampMilliseconds: timestamp
            ) else {
                identity.noteMissing(timestamp: CMTimeGetSeconds(frame.timestamp))
                throw Guidance("No hand found. Bring your hand back into view.")
            }
            guard detection.handCount == 1 else {
                identity.reset()
                throw Guidance("Show one hand only, then face your palm toward the camera.")
            }
            let mapped = try DepthLandmarkMapper.map(
                modelPoints: detection.points, depth: frame.depthData,
                orientation: frame.imageOrientation, confidence: detection.confidence,
                videoWidth: CVPixelBufferGetWidth(frame.pixelBuffer),
                videoHeight: CVPixelBufferGetHeight(frame.pixelBuffer)
            )
            points = mapped.sensorPoints
            depthCount = mapped.landmarks.count
            distance = mapped.distanceMeters
            let depthMap = frame.depthData.depthDataMap
            diagnostics = "RGB \(CVPixelBufferGetWidth(frame.pixelBuffer))×\(CVPixelBufferGetHeight(frame.pixelBuffer)) · Depth \(CVPixelBufferGetWidth(depthMap))×\(CVPixelBufferGetHeight(depthMap)) · Label \(detection.label) \(Int(detection.confidence * 100))%"
            guard detection.points.allSatisfy({ (0.03...0.97).contains($0.x) && (0.03...0.97).contains($0.y) }) else {
                throw Guidance("Center your full hand inside the camera.")
            }
            guard let meters = distance else { throw Guidance("Depth is missing. Change the hand angle slightly.") }
            if meters < 0.20 { throw Guidance("Move farther away.") }
            if meters > 0.65 { throw Guidance("Move closer.") }
            let identityScore: Double
            switch identity.update(
                detectedHand: ScannerAdapterGeometry.physicalHandedness(label: detection.label, convention: .subjectHand),
                labelConfidence: detection.confidence, observedView: classify(detection.worldPoints),
                sensorPoints: mapped.sensorPoints.map { PixelPoint(x: Double($0.x), y: Double($0.y)) },
                timestamp: CMTimeGetSeconds(frame.timestamp), palmNormalZ: palmNormal(detection.worldPoints)?.z
            ) {
            case .tracked(let score): identityScore = score
            case .wrongHand:
                throw Guidance("Show your \(hand.rawValue) palm to identify the correct hand.")
            case .confirmingPalm:
                throw Guidance("Recognizing your \(hand.rawValue) hand. Keep your palm facing the camera briefly.")
            case .showPalm:
                throw Guidance(session.coverage.snapshot.capturedViews.isEmpty
                    ? "Face your palm toward the camera in even light so we can identify your hand."
                    : "Show your palm briefly to reconnect tracking. Your completed views are saved.")
            }
            let expectedView = session.coverage.snapshot.currentView
            let classifiedView = classify(detection.worldPoints, requested: expectedView)
            diagnostics += " · View seen: \(classifiedView?.rawValue ?? "between views")"
            guard let observedView = classifiedView else {
                consecutiveViewFrames = 0
                stability.reset()
                recentDepth.reset()
                let sideRequested = expectedView == .thumbSide || expectedView == .pinkySide
                throw Guidance(sideRequested
                    ? "Turn back slightly until every finger is visible. Don’t hold your hand fully edge-on."
                    : session.coverage.snapshot.nextInstruction)
            }
            guard observedView == expectedView else {
                consecutiveViewFrames = 0
                stability.reset()
                recentDepth.reset()
                throw Guidance(session.coverage.snapshot.nextInstruction)
            }
            if previousView == observedView { consecutiveViewFrames += 1 }
            else { previousView = observedView; consecutiveViewFrames = 1 }
            guard consecutiveViewFrames >= 3 else { throw Guidance("Hold still.", preserveHistory: true) }
            joints.record(validLandmarks: Set(mapped.landmarks.keys), view: observedView)
            // Confidence describes the acquired palm identity, not the ambiguous
            // current side-view label and not measurement accuracy. Metric checks
            // below independently decide whether measured geometry is acceptable.
            let identifiedLandmarks = mapped.landmarks.mapValues {
                NamedLandmark(name: $0.name, point: $0.point, confidence: identityScore)
            }
            let measured = recentDepth.record(
                identifiedLandmarks, view: observedView, timestamp: CMTimeGetSeconds(frame.timestamp)
            )
            guard measured.count == 21 else {
                stability.reset()
                let missing = Set(HandLandmarkName.allCases.filter { measured[$0] == nil }.map {
                    String($0.rawValue.prefix(while: { $0.isLowercase }))
                }).sorted().joined(separator: ", ")
                throw Guidance("Missing depth: \(missing). Spread your fingers and tilt slightly.", preserveHistory: true)
            }
            guard stability.accept(measured) else {
                let reason: String
                switch stability.status {
                case .moving: reason = "Keep the phone steady and rest your arm while we capture."
                case .overlappingFingers: reason = "Your fingers overlap in this angle. Turn slightly back until each finger is visible."
                case .noisyDepth: reason = "Depth is fluctuating. Hold your hand still at 30–40 cm."
                case .incompleteDepth: reason = "Some finger depth is missing. Tilt your hand slightly."
                case .settling, .ready: reason = "Angle found. Pause briefly while we capture."
                }
                throw Guidance(reason, preserveHistory: true)
            }
            try session.accept(ScanObservation(
                view: observedView, handedness: hand,
                landmarks: measured, frameConfidence: identityScore
            ))
            counts[observedView, default: 0] += 1
            message = session.coverage.snapshot.currentView == observedView
                ? "Hold still. Capturing this view…" : session.coverage.snapshot.nextInstruction
            if session.coverage.snapshot.isComplete {
                let profile = try session.makeProfile(
                    profileId: UUID().uuidString, createdAt: ISO8601DateFormatter().string(from: Date())
                )
                var extensions = profile.extensions
                extensions["gripit.demo"] = .object([
                    "acceptedFramesByView": .object(Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, .number(Double($0.value))) })),
                    "validation": .string("experimental; compare with physical measurements"),
                    "depthSource": .string("synchronized-front-truedepth"),
                    "depthHoleHandling": .string("measured-only; same view; maximum age 350ms; resets on motion"),
                    "landmarkConfidenceSource": .string("initial palm identity score retained only across continuous tracking; not metric accuracy"),
                    "sideViewPolicy": .string("oblique side views with visible fingers; edge-on poses rejected"),
                    "orientationSource": .string("MediaPipe model world landmarks; not metric measurements")
                ])
                result = HandProfile(
                    profileId: profile.profileId, createdAt: profile.createdAt, handedness: profile.handedness,
                    measurements: profile.measurements, landmarks: profile.landmarks,
                    capture: profile.capture, extensions: extensions
                )
                message = "Scan complete. Compare these measurements with a ruler."
                diagnostics += " · " + ScanView.requiredOrder.map { "\($0.rawValue): \(counts[$0, default: 0])" }.joined(separator: " · ")
            }
        } catch let guidance as Guidance {
            message = guidance.text
            if !guidance.preserveHistory {
                stability.reset()
                recentDepth.reset()
                consecutiveViewFrames = 0
                previousView = nil
            }
        } catch {
            stability.reset()
            recentDepth.reset()
            consecutiveViewFrames = 0
            message = error.localizedDescription
        }
        let view = session.coverage.snapshot.currentView
        let fractions = Dictionary(uniqueKeysWithValues: HandLandmarkName.allCases.map { name in
            (name, view.map { joints.snapshot.fraction(for: name, in: $0) } ?? 1)
        })
        return ScannerFrameUpdate(
            points: points,
            sensorSize: CGSize(width: CVPixelBufferGetWidth(frame.pixelBuffer), height: CVPixelBufferGetHeight(frame.pixelBuffer)),
            validDepthCount: depthCount, distanceMeters: distance,
            coverage: session.coverage.snapshot, jointFractions: fractions,
            message: message, diagnostics: diagnostics, profile: result,
            initializationFailed: initializationFailed,
            trackingStatus: identity.identityConfidence == nil ? "Identifying hand" : "\(hand.rawValue.capitalized) hand tracked"
        )
    }

    private func classify(_ world: [SIMD3<Double>], requested: ScanView? = nil) -> ScanView? {
        guard let normal = palmNormal(world) else { return nil }
        if let requested, ScannerAdapterGeometry.matchesView(
            normalX: normal.x, normalZ: normal.z, handedness: hand, requested: requested
        ) { return requested }
        let observed = ScannerAdapterGeometry.classifyView(
            normalX: normal.x, normalZ: normal.z, handedness: hand
        )
        // A requested side must satisfy the measurable oblique range. Do not
        // accidentally accept the old classifier's fully edge-on side result.
        return requested != nil && observed == requested ? nil : observed
    }

    private func palmNormal(_ world: [SIMD3<Double>]) -> SIMD3<Double>? {
        guard world.count == 21 else { return nil }
        let lateral = world[5] - world[17]
        let fingers = world[9] - world[0]
        let cross = simd_cross(lateral, fingers)
        let length = simd_length(cross)
        guard length.isFinite, length > 0.000001 else { return nil }
        return cross / length
    }

    private struct Guidance: Error {
        let text: String
        let preserveHistory: Bool
        init(_ text: String, preserveHistory: Bool = false) {
            self.text = text
            self.preserveHistory = preserveHistory
        }
    }
}
