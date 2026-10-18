import GripItScannerCore
import SwiftUI

struct SkeletonCoverageView: View {
    let fractions: [HandLandmarkName: Double]

    private let missingColor = Color.white.opacity(0.28)
    private let samplingColor = Color.orange
    private let completeColor = Color.mint

    var body: some View {
        Canvas { context, size in
            let locations = Self.locations.mapValues {
                CGPoint(x: $0.x * size.width, y: $0.y * size.height)
            }

            for (start, end) in Self.edges {
                guard let first = locations[start], let second = locations[end] else { continue }
                var segment = Path()
                segment.move(to: first)
                segment.addLine(to: second)
                context.stroke(segment, with: .color(missingColor), lineWidth: 2)

                let fraction = min(progress(for: start), progress(for: end))
                if fraction > 0 {
                    context.stroke(
                        segment,
                        with: .color(fraction >= 1 ? completeColor : samplingColor),
                        lineWidth: 2
                    )
                }
            }

            for name in HandLandmarkName.allCases {
                guard let point = locations[name] else { continue }
                let radius = max(2, min(size.width, size.height) * 0.035)
                let circleRect = CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                let circle = Path(ellipseIn: circleRect)
                context.fill(circle, with: .color(Color.black.opacity(0.72)))

                let fraction = progress(for: name)
                if fraction > 0 {
                    let fillRect = CGRect(
                        x: circleRect.minX,
                        y: circleRect.maxY - circleRect.height * fraction,
                        width: circleRect.width,
                        height: circleRect.height * fraction
                    )
                    context.drawLayer { layer in
                        layer.clip(to: Path(fillRect))
                        layer.fill(
                            circle,
                            with: .color(fraction >= 1 ? completeColor : samplingColor)
                        )
                    }
                }
                context.stroke(circle, with: .color(missingColor), lineWidth: 1)
            }
        }
        .aspectRatio(0.72, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Current view skeletal coverage")
        .accessibilityValue(accessibilitySummary)

    }

    private func progress(for name: HandLandmarkName) -> Double {
        min(max(fractions[name] ?? 0, 0), 1)
    }

    private var accessibilitySummary: String {
        let complete = HandLandmarkName.allCases.filter { progress(for: $0) >= 1 }.count
        let sampling = HandLandmarkName.allCases.filter {
            let value = progress(for: $0)
            return value > 0 && value < 1
        }.count
        return "\(complete) complete, \(sampling) sampling, \(21 - complete - sampling) missing"
    }

    private static let locations: [HandLandmarkName: CGPoint] = [
        .wrist: CGPoint(x: 0.50, y: 0.96),
        .thumbCMC: CGPoint(x: 0.38, y: 0.80),
        .thumbMCP: CGPoint(x: 0.27, y: 0.69),
        .thumbIP: CGPoint(x: 0.18, y: 0.59),
        .thumbTip: CGPoint(x: 0.08, y: 0.51),
        .indexMCP: CGPoint(x: 0.39, y: 0.64),
        .indexPIP: CGPoint(x: 0.36, y: 0.44),
        .indexDIP: CGPoint(x: 0.35, y: 0.27),
        .indexTip: CGPoint(x: 0.34, y: 0.10),
        .middleMCP: CGPoint(x: 0.50, y: 0.61),
        .middlePIP: CGPoint(x: 0.50, y: 0.37),
        .middleDIP: CGPoint(x: 0.50, y: 0.18),
        .middleTip: CGPoint(x: 0.50, y: 0.03),
        .ringMCP: CGPoint(x: 0.61, y: 0.64),
        .ringPIP: CGPoint(x: 0.64, y: 0.43),
        .ringDIP: CGPoint(x: 0.65, y: 0.27),
        .ringTip: CGPoint(x: 0.66, y: 0.11),
        .pinkyMCP: CGPoint(x: 0.72, y: 0.70),
        .pinkyPIP: CGPoint(x: 0.77, y: 0.54),
        .pinkyDIP: CGPoint(x: 0.80, y: 0.42),
        .pinkyTip: CGPoint(x: 0.82, y: 0.31),
    ]

    private static let edges: [(HandLandmarkName, HandLandmarkName)] = [
        (.wrist, .thumbCMC), (.thumbCMC, .thumbMCP), (.thumbMCP, .thumbIP),
        (.thumbIP, .thumbTip), (.wrist, .indexMCP), (.indexMCP, .indexPIP),
        (.indexPIP, .indexDIP), (.indexDIP, .indexTip), (.indexMCP, .middleMCP),
        (.middleMCP, .middlePIP), (.middlePIP, .middleDIP), (.middleDIP, .middleTip),
        (.middleMCP, .ringMCP), (.ringMCP, .ringPIP), (.ringPIP, .ringDIP),
        (.ringDIP, .ringTip), (.ringMCP, .pinkyMCP), (.pinkyMCP, .pinkyPIP),
        (.pinkyPIP, .pinkyDIP), (.pinkyDIP, .pinkyTip), (.pinkyMCP, .wrist),
    ]
}
