public enum HandMeasurementError: Error, Equatable, Sendable {
    case noCompleteFrames
    case missingLandmark(HandLandmarkName)
}

public struct HandMeasurementAggregator: Sendable {
    public init() {}

    public func measure(_ observations: [ScanObservation]) throws -> HandMeasurements {
        guard !observations.isEmpty else {
            throw HandMeasurementError.noCompleteFrames
        }
        let frames = try observations.map(measureFrame)

        return HandMeasurements(
            palm: PalmMeasurements(
                widthMm: median(frames.map(\.palmWidth)),
                lengthMm: median(frames.map(\.palmLength)),
                thicknessMm: nil
            ),
            fingers: FingerMeasurementSet(
                index: aggregateFinger(frames.map(\.index)),
                middle: aggregateFinger(frames.map(\.middle)),
                ring: aggregateFinger(frames.map(\.ring)),
                pinky: aggregateFinger(frames.map(\.pinky)),
                thumb: aggregateFinger(frames.map(\.thumb))
            )
        )
    }

    private func measureFrame(_ observation: ScanObservation) throws -> FrameMeasurements {
        func point(_ name: HandLandmarkName) throws -> MetricPoint3D {
            guard let point = observation.landmarks[name]?.point else {
                throw HandMeasurementError.missingLandmark(name)
            }
            return point
        }

        func segments(_ names: [HandLandmarkName]) throws -> [Double] {
            try zip(names, names.dropFirst()).map { first, second in
                try point(first).distance(to: point(second))
            }
        }

        let wrist = try point(.wrist)
        let indexMCP = try point(.indexMCP)
        let pinkyMCP = try point(.pinkyMCP)
        let palmCenter = MetricPoint3D(
            xMm: (indexMCP.xMm + pinkyMCP.xMm) / 2,
            yMm: (indexMCP.yMm + pinkyMCP.yMm) / 2,
            zMm: (indexMCP.zMm + pinkyMCP.zMm) / 2
        )

        return FrameMeasurements(
            palmWidth: indexMCP.distance(to: pinkyMCP),
            palmLength: wrist.distance(to: palmCenter),
            index: try segments([.indexMCP, .indexPIP, .indexDIP, .indexTip]),
            middle: try segments([.middleMCP, .middlePIP, .middleDIP, .middleTip]),
            ring: try segments([.ringMCP, .ringPIP, .ringDIP, .ringTip]),
            pinky: try segments([.pinkyMCP, .pinkyPIP, .pinkyDIP, .pinkyTip]),
            thumb: try segments([.thumbCMC, .thumbMCP, .thumbIP, .thumbTip])
        )
    }

    private func aggregateFinger(_ samples: [[Double]]) -> FingerMeasurements {
        let count = samples.map(\.count).min() ?? 0
        let segments = (0 ..< count).map { index in
            median(samples.map { $0[index] })
        }
        return FingerMeasurements(segmentsMm: segments, diameterMm: nil)
    }
}

private struct FrameMeasurements {
    let palmWidth: Double
    let palmLength: Double
    let index: [Double]
    let middle: [Double]
    let ring: [Double]
    let pinky: [Double]
    let thumb: [Double]
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}
