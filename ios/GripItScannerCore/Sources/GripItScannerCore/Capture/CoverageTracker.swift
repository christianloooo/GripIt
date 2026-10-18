public struct CoverageSnapshot: Equatable, Sendable {
    public let requiredViews: [ScanView]
    public let capturedViews: [ScanView]
    public let currentView: ScanView?
    public let acceptedFramesInCurrentView: Int
    public let minimumFramesPerView: Int
    public let fraction: Double
    public let isComplete: Bool
    public let nextInstruction: String
}

public enum CoverageError: Error, Equatable, Sendable {
    case invalidConfiguration
    case scanComplete
    case unexpectedView(expected: ScanView, actual: ScanView)
    case noLandmarks
    case incompleteLandmarks
    case landmarkNameMismatch(key: HandLandmarkName, value: HandLandmarkName)
    case invalidConfidence
    case nonFiniteLandmark(HandLandmarkName)
    case lowConfidence
}

public struct CoverageTracker: Sendable {
    public let minimumFramesPerView: Int
    public let minimumConfidence: Double

    private var completedViews: [ScanView] = []
    private var acceptedFrames = 0

    public init(minimumFramesPerView: Int = 8, minimumConfidence: Double = 0.8) {
        self.minimumFramesPerView = minimumFramesPerView
        self.minimumConfidence = minimumConfidence
    }

    public var snapshot: CoverageSnapshot {
        let currentView = completedViews.count < ScanView.requiredOrder.count
            ? ScanView.requiredOrder[completedViews.count]
            : nil
        let partialView = minimumFramesPerView > 0
            ? Double(acceptedFrames) / Double(minimumFramesPerView)
            : 0
        let fraction = (Double(completedViews.count) + partialView)
            / Double(ScanView.requiredOrder.count)
        return CoverageSnapshot(
            requiredViews: ScanView.requiredOrder,
            capturedViews: completedViews,
            currentView: currentView,
            acceptedFramesInCurrentView: acceptedFrames,
            minimumFramesPerView: minimumFramesPerView,
            fraction: fraction,
            isComplete: currentView == nil,
            nextInstruction: Self.instruction(for: currentView)
        )
    }

    public mutating func accept(_ observation: ScanObservation) throws {
        guard minimumFramesPerView > 0, (0 ... 1).contains(minimumConfidence) else {
            throw CoverageError.invalidConfiguration
        }
        guard let expectedView = snapshot.currentView else {
            throw CoverageError.scanComplete
        }
        guard observation.view == expectedView else {
            throw CoverageError.unexpectedView(expected: expectedView, actual: observation.view)
        }
        guard !observation.landmarks.isEmpty else {
            throw CoverageError.noLandmarks
        }
        guard Set(observation.landmarks.keys) == Set(HandLandmarkName.allCases) else {
            throw CoverageError.incompleteLandmarks
        }
        guard observation.frameConfidence.isFinite,
              (0 ... 1).contains(observation.frameConfidence)
        else {
            throw CoverageError.invalidConfidence
        }
        guard observation.frameConfidence >= minimumConfidence else {
            throw CoverageError.lowConfidence
        }
        for (key, landmark) in observation.landmarks {
            guard key == landmark.name else {
                throw CoverageError.landmarkNameMismatch(key: key, value: landmark.name)
            }
            guard landmark.confidence.isFinite,
                  (0 ... 1).contains(landmark.confidence)
            else {
                throw CoverageError.invalidConfidence
            }
            guard landmark.confidence >= minimumConfidence else {
                throw CoverageError.lowConfidence
            }
            guard landmark.point.xMm.isFinite,
                  landmark.point.yMm.isFinite,
                  landmark.point.zMm.isFinite
            else {
                throw CoverageError.nonFiniteLandmark(key)
            }
        }

        acceptedFrames += 1
        if acceptedFrames == minimumFramesPerView {
            completedViews.append(expectedView)
            acceptedFrames = 0
        }
    }

    private static func instruction(for view: ScanView?) -> String {
        switch view {
        case .palm: "Show your palm and spread your fingers."
        case .back: "Rotate until the back of your hand faces the camera."
        case .thumbSide: "Turn your thumb slightly toward the camera. Keep all fingers visible, not edge-on."
        case .pinkySide: "Turn your pinky slightly toward the camera. Keep all fingers visible, not edge-on."
        case nil: "Scan complete."
        }
    }
}
