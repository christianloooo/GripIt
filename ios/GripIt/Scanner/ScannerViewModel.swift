import AVFoundation
import Combine
import OSLog
import GripItScannerCore
import SwiftUI
import UIKit


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
    @Published var gate = ScanGateReport()
    @Published var showGatePanel = false
    @Published var exportURL: URL?

    private static let log = Logger(subsystem: "com.gripit.scanner", category: "gates")
    private let capture = TrueDepthCaptureService()
    private var generation = UUID()
    var captureSession: AVCaptureSession { capture.session }

    init() {
        if let saved = SavedHandProfile.latest() {
            profile = saved
            selectedHand = saved.handedness
            phase = .complete
            progress = 1
            currentView = nil
            message = "Your saved hand measurements are ready."
            diagnostics = "Saved hand profile · scan again to replace it"
        }
    }

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
        gate = ScanGateReport()
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

    func loadProfile(from url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= 1_000_000 else {
            throw GripError.invalid("Choose a HandProfile JSON file under 1 MB.")
        }
        let imported = try HandProfileCodec.decode(data)
        guard imported.coordinateSystem == "gripit-hand-v1" else {
            throw GripError.invalid("Unsupported hand coordinate system.")
        }
        reset()
        profile = imported
        selectedHand = imported.handedness
        phase = .complete
        progress = 1
        currentView = nil
        message = "Imported hand measurements are ready."
        diagnostics = "Imported HandProfile · camera was not used"
        exportProfile()
    }

    func exportProfile() {
        guard let profile else { return }
        do {
            removeExport()
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("gripit-hand-\(profile.profileId).json")
            try HandProfileCodec.encode(profile).write(to: file, options: .atomic)
            if !profile.capture.method.localizedCaseInsensitiveContains("sample") {
                try SavedHandProfile.save(profile)
            }
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
        if gate.gate != update.gate.gate {
            Self.log.info("""
                gate=\(update.gate.gate, privacy: .public)                 identity=\(update.gate.identity, privacy: .public)                 label=\(update.gate.label, privacy: .public)                 facing=\(update.gate.facing, privacy: .public)                 pose=\(update.gate.poseMatch, privacy: .public)                 held=\(update.gate.poseFrames, privacy: .public)                 depth=\(update.gate.depth, privacy: .public)                 steady=\(update.gate.stability, privacy: .public)                 accepted=\(update.gate.accepted, privacy: .public)                 frame=\(update.gate.frame, privacy: .public)
                """)
        }
        gate = update.gate
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


/// Every number the scan gates actually decided on, for the on-screen panel.
/// Built fresh each frame so a stalled scan names its own blocking gate instead
/// of leaving the cause to be guessed at.
struct ScanGateReport: Sendable, Equatable {
    var gate = "starting camera"
    var identity = "unlocked"
    var label = "—"
    var facing = "—"
    var poseMatch = "—"
    var poseFrames = "—"
    var depth = "—"
    var stability = "—"
    var accepted = "—"
    var frame = "—"

    var rows: [(String, String)] {
        [
            ("blocked by", gate),
            ("identity", identity),
            ("label", label),
            ("facing", facing),
            ("pose", poseMatch),
            ("held", poseFrames),
            ("depth", depth),
            ("steady", stability),
            ("accepted", accepted),
            ("frame", frame),
        ]
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
    let gate: ScanGateReport
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

    private static let requiredPoseFrames = 3

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
        var gate = ScanGateReport()
        gate.accepted = "\(session.coverage.snapshot.acceptedFramesInCurrentView)/8"
            + " · \(session.coverage.snapshot.currentView?.rawValue ?? "done")"
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
                throw Guidance("No hand found. Bring your hand back into view.", gate: "no hand detected")
            }
            gate.label = "\(detection.label) \(Int((detection.confidence * 100).rounded()))%"
            guard detection.handCount == 1 else {
                identity.reset()
                throw Guidance(
                    "Show one hand only, then face your palm toward the camera.",
                    gate: "\(detection.handCount) hands in view"
                )
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
            gate.frame = "RGB \(CVPixelBufferGetWidth(frame.pixelBuffer))×\(CVPixelBufferGetHeight(frame.pixelBuffer))"
                + " · depth \(CVPixelBufferGetWidth(depthMap))×\(CVPixelBufferGetHeight(depthMap))"
                + " · rot \(frame.imageOrientation.rotationLabel)"
            gate.depth = "\(depthCount)/21 now"
            diagnostics = gate.frame + " · Label \(gate.label)"
            guard detection.points.allSatisfy({ (0.03...0.97).contains($0.x) && (0.03...0.97).contains($0.y) }) else {
                throw Guidance("Center your full hand inside the camera.", gate: "hand touches frame edge")
            }
            guard let meters = distance else {
                throw Guidance("Depth is missing. Change the hand angle slightly.", gate: "no valid depth")
            }
            gate.depth += " · \(Int((meters * 100).rounded())) cm"
            if meters < 0.20 { throw Guidance("Move farther away.", gate: "too close (\(Int((meters * 100).rounded())) cm)") }
            if meters > 0.65 { throw Guidance("Move closer.", gate: "too far (\(Int((meters * 100).rounded())) cm)") }

            // Orientation comes from the TrueDepth measurements, in the hand's
            // own basis. Measured depth fixes the sign of "toward the camera";
            // MediaPipe's world landmarks only guess it from one image, and the
            // side views are precisely the poses that guess gets wrong.
            let facing = ScannerAdapterGeometry.handFacing(
                measured: mapped.landmarks.mapValues(\.point), handedness: hand
            )
            gate.facing = facing.map {
                String(format: "palm %+.2f · thumb %+.2f · tips %+.2f", $0.palm, $0.thumb, $0.fingers)
            } ?? "palm anchors lack depth"
            guard facing != nil else {
                throw Guidance(
                    "Show your whole palm squarely for a moment so we can measure its angle.",
                    gate: "orientation: no depth at wrist or knuckles"
                )
            }

            let identityScore: Double
            switch identity.update(
                detectedHand: ScannerAdapterGeometry.physicalHandedness(label: detection.label, convention: .subjectHand),
                labelConfidence: detection.confidence,
                observedView: facing.flatMap(ScannerAdapterGeometry.classifyView),
                sensorPoints: mapped.sensorPoints.map { PixelPoint(x: Double($0.x), y: Double($0.y)) },
                timestamp: CMTimeGetSeconds(frame.timestamp), palmFacing: facing?.palm
            ) {
            case .tracked(let score): identityScore = score
            case .wrongHand:
                throw Guidance(
                    "Show your \(hand.rawValue) palm to identify the correct hand.",
                    gate: "identity: reads as the other hand"
                )
            case .confirmingPalm:
                throw Guidance(
                    "Recognizing your \(hand.rawValue) hand. Keep your palm facing the camera briefly.",
                    gate: "identity: confirming palm"
                )
            case .showPalm:
                throw Guidance(session.coverage.snapshot.capturedViews.isEmpty
                    ? "Face your palm toward the camera in even light so we can identify your hand."
                    : "Show your palm briefly to reconnect tracking. Your completed views are saved.",
                    gate: "identity: needs a palm to lock on")
            }
            gate.identity = "locked \(Int((identityScore * 100).rounded()))%"

            let expectedView = session.coverage.snapshot.currentView
            let classifiedView = classify(facing, requested: expectedView)
            gate.poseMatch = "want \(expectedView?.rawValue ?? "done")"
                + " · see \(classifiedView?.rawValue ?? "between views")"
            diagnostics += " · View seen: \(classifiedView?.rawValue ?? "between views")"
            guard let observedView = classifiedView else {
                consecutiveViewFrames = 0
                stability.reset()
                recentDepth.reset()
                throw Guidance(betweenViewsGuidance(expectedView, facing: facing),
                               gate: "pose: between views")
            }
            guard observedView == expectedView else {
                consecutiveViewFrames = 0
                stability.reset()
                recentDepth.reset()
                throw Guidance(session.coverage.snapshot.nextInstruction,
                               gate: "pose: showing \(observedView.rawValue)")
            }
            if previousView == observedView { consecutiveViewFrames += 1 }
            else { previousView = observedView; consecutiveViewFrames = 1 }
            gate.poseFrames = "\(min(consecutiveViewFrames, Self.requiredPoseFrames))/\(Self.requiredPoseFrames) pose frames"
            guard consecutiveViewFrames >= Self.requiredPoseFrames else {
                throw Guidance("Hold still.", preserveHistory: true, gate: "pose: settling")
            }
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
            gate.depth = "\(depthCount)/21 now · \(measured.count)/21 bridged"
                + " · \(Int((meters * 100).rounded())) cm"
            guard measured.count == 21 else {
                stability.reset()
                let missing = Set(HandLandmarkName.allCases.filter { measured[$0] == nil }.map {
                    String($0.rawValue.prefix(while: { $0.isLowercase }))
                }).sorted().joined(separator: ", ")
                throw Guidance(
                    "Missing depth: \(missing). Spread your fingers and tilt slightly.",
                    preserveHistory: true, gate: "depth holes: \(missing)"
                )
            }
            let steady = stability.accept(measured)
            gate.stability = stabilitySummary()
            guard steady else {
                let reason: String
                switch stability.status {
                case .moving: reason = "Keep the phone steady and rest your arm while we capture."
                case .overlappingFingers: reason = "Your fingers overlap in this angle. Turn slightly back until each finger is visible."
                case .noisyDepth: reason = "Depth is fluctuating. Hold your hand still at 30–40 cm."
                case .incompleteDepth: reason = "Some finger depth is missing. Tilt your hand slightly."
                case .settling, .ready: reason = "Angle found. Pause briefly while we capture."
                }
                throw Guidance(reason, preserveHistory: true, gate: "steady: \(stability.status.label)")
            }
            try session.accept(ScanObservation(
                view: observedView, handedness: hand,
                landmarks: measured, frameConfidence: identityScore
            ))
            counts[observedView, default: 0] += 1
            gate.gate = "none · capturing \(observedView.rawValue)"
            gate.accepted = "\(session.coverage.snapshot.acceptedFramesInCurrentView)/8"
                + " · \(session.coverage.snapshot.currentView?.rawValue ?? "done")"
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
                    "orientationSource": .string("MediaPipe model world landmarks resolved in the hand's own basis; invariant to image-plane roll; not metric measurements")
                ])
                result = HandProfile(
                    profileId: profile.profileId, createdAt: profile.createdAt, handedness: profile.handedness,
                    measurements: profile.measurements, landmarks: profile.landmarks,
                    capture: profile.capture, extensions: extensions
                )
                message = "Scan complete. Compare these measurements with a ruler."
                gate.gate = "none · scan complete"
                diagnostics += " · " + ScanView.requiredOrder.map { "\($0.rawValue): \(counts[$0, default: 0])" }.joined(separator: " · ")
            }
        } catch let guidance as Guidance {
            message = guidance.text
            gate.gate = guidance.gate
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
            gate.gate = "error: \(error.localizedDescription)"
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
            trackingStatus: identity.identityConfidence == nil ? "Identifying hand" : "\(hand.rawValue.capitalized) hand tracked",
            gate: gate
        )
    }

    private func stabilitySummary() -> String {
        var parts = ["\(stability.status.label) \(stability.stableComparisons)/\(MeasurementStabilityGate.requiredStableComparisons)"]
        if let motion = stability.motionRms {
            parts.append(String(format: "motion %.1f/%.0f mm", motion, MeasurementStabilityGate.motionLimitMm))
        }
        if let change = stability.worstBoneChangeMm {
            parts.append(String(format: "bone Δ%.1f mm", change))
        }
        if let shortest = stability.shortestBoneMm {
            parts.append(String(format: "min bone %.0f mm", shortest))
        }
        return parts.joined(separator: " · ")
    }

    private func classify(_ facing: HandFacing?, requested: ScanView? = nil) -> ScanView? {
        guard let facing else { return nil }
        if let requested, ScannerAdapterGeometry.matchesView(facing, requested: requested) {
            return requested
        }
        let observed = ScannerAdapterGeometry.classifyView(facing)
        // A requested view must satisfy the measurable window above. Never let the
        // nearest-view classifier wave through a pose that window rejected.
        return requested != nil && observed == requested ? nil : observed
    }

    /// Names the one thing to change, using the component that fell short.
    private func betweenViewsGuidance(_ requested: ScanView?, facing: HandFacing?) -> String {
        guard let requested, let facing else {
            return session.coverage.snapshot.nextInstruction
        }
        if abs(facing.fingers) > ScannerAdapterGeometry.fingertipFacingLimit {
            return "Your fingertips point at the camera. Raise your fingers so the camera sees their length."
        }
        switch requested {
        case .palm, .back:
            return session.coverage.snapshot.nextInstruction
        case .thumbSide, .pinkySide:
            let side = requested == .thumbSide ? "thumb" : "pinky"
            if abs(facing.palm) < ScannerAdapterGeometry.sideObliqueFloor {
                return "Too edge-on. Turn back slightly until some of your palm shows again."
            }
            // The thumb component is signed, so it says whether they are turning
            // toward the requested side or away from it.
            let wanted = requested == .thumbSide ? facing.thumb : -facing.thumb
            if wanted < 0 {
                return "You are turning the wrong way. Rotate back the other way to bring your \(side) side toward the camera."
            }
            return "Turn a little further until your \(side) side faces the camera. Keep every finger visible."
        }
    }

    private struct Guidance: Error {
        let text: String
        let preserveHistory: Bool
        let gate: String
        init(_ text: String, preserveHistory: Bool = false, gate: String) {
            self.text = text
            self.preserveHistory = preserveHistory
            self.gate = gate
        }
    }
}

private extension MeasurementStabilityStatus {
    var label: String {
        switch self {
        case .settling: "settling"
        case .incompleteDepth: "incomplete depth"
        case .overlappingFingers: "fingers overlap"
        case .noisyDepth: "noisy depth"
        case .moving: "moving"
        case .ready: "ready"
        }
    }
}

private extension UIImage.Orientation {
    var rotationLabel: String {
        switch self {
        case .up: "0°"
        case .right: "90°"
        case .down: "180°"
        case .left: "270°"
        default: "mirrored"
        }
    }
}

/// One local profile per app installation. Demo samples never replace a real scan.
enum SavedHandProfile {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GripIt/hand-profile.json")
    }
    static func load(from file: URL = url) -> HandProfile? {
        guard let data = try? Data(contentsOf: file),
              let profile = try? HandProfileCodec.decode(data),
              !profile.capture.method.localizedCaseInsensitiveContains("sample") else { return nil }
        return profile
    }
    static func latest(exportDirectory: URL = FileManager.default.temporaryDirectory, savedFile: URL = url) -> HandProfile? {
        if let saved = load(from: savedFile) { return saved }
        // Upgrade earlier builds that exported scans only into the app's tmp folder.
        let files = (try? FileManager.default.contentsOfDirectory(at: exportDirectory,
            includingPropertiesForKeys: nil)) ?? []
        let recovered = files.filter {
            $0.lastPathComponent.hasPrefix("gripit-hand-") && $0.pathExtension == "json"
        }.compactMap { load(from: $0) }.max { $0.createdAt < $1.createdAt }
        if let recovered { try? save(recovered, to: savedFile) }
        return recovered
    }
    static func save(_ profile: HandProfile, to file: URL = url) throws {
        guard !profile.capture.method.localizedCaseInsensitiveContains("sample") else { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try HandProfileCodec.encode(profile).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
