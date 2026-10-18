import Foundation

/// Image orientation is analysis-only. The camera preview may mirror independently.
public enum SensorImageRotation: Sendable {
    case up, down, left, right

    public func sensorPoint(fromModel point: PixelPoint) -> PixelPoint {
        switch self {
        case .up: point
        case .down: PixelPoint(x: 1 - point.x, y: 1 - point.y)
        case .left: PixelPoint(x: 1 - point.y, y: point.x)
        case .right: PixelPoint(x: point.y, y: 1 - point.x)
        }
    }
}

public enum ScannerAdapterGeometry {
    public enum HandLabelConvention: Sendable { case subjectHand, mirroredViewer }

    public static func physicalHandedness(
        label: String, convention: HandLabelConvention
    ) -> Handedness? {
        guard let hand = Handedness(rawValue: label.lowercased()) else { return nil }
        switch convention {
        case .subjectHand: return hand
        case .mirroredViewer: return hand == .left ? .right : .left
        }
    }

    /// Rectifies one distorted pixel using Apple's relative radial magnification table.
    /// Depth lookup still uses the original distorted pixel that aligns with RGB.
    public static func rectifiedPixel(
        _ pixel: PixelPoint, center: PixelPoint,
        width: Double, height: Double, lookupTable: [Double]
    ) -> PixelPoint? {
        guard lookupTable.count >= 2, lookupTable.allSatisfy(\.isFinite),
              [pixel.x, pixel.y, center.x, center.y, width, height].allSatisfy(\.isFinite),
              width > 0, height > 0 else { return nil }
        let dx = pixel.x - center.x
        let dy = pixel.y - center.y
        let maxX = max(center.x, width - center.x)
        let maxY = max(center.y, height - center.y)
        let maxRadius = hypot(maxX, maxY)
        guard maxRadius > 0 else { return nil }
        let index = min(Double(lookupTable.count - 1), hypot(dx, dy) / maxRadius * Double(lookupTable.count - 1))
        let lower = Int(index)
        let upper = min(lower + 1, lookupTable.count - 1)
        let fraction = index - Double(lower)
        let magnitude = lookupTable[lower] * (1 - fraction) + lookupTable[upper] * fraction
        return PixelPoint(x: center.x + dx * (1 + magnitude), y: center.y + dy * (1 + magnitude))
    }

    public static func medianValidDepth(_ values: [Double]) -> Double? {
        let valid = values.filter { $0.isFinite && (0.12 ... 1.2).contains($0) }.sorted()
        guard !valid.isEmpty else { return nil }
        let middle = valid.count / 2
        return valid.count.isMultiple(of: 2)
            ? (valid[middle - 1] + valid[middle]) / 2 : valid[middle]
    }

    public static func scaledIntrinsics(
        fx: Double, fy: Double, cx: Double, cy: Double,
        referenceWidth: Double, referenceHeight: Double,
        depthWidth: Int, depthHeight: Int
    ) -> CameraIntrinsics? {
        guard [fx, fy, cx, cy, referenceWidth, referenceHeight].allSatisfy(\.isFinite),
              fx > 0, fy > 0, referenceWidth > 0, referenceHeight > 0,
              depthWidth > 0, depthHeight > 0 else { return nil }
        let sx = Double(depthWidth) / referenceWidth
        let sy = Double(depthHeight) / referenceHeight
        return CameraIntrinsics(fx: fx * sx, fy: fy * sy, cx: cx * sx, cy: cy * sy)
    }

    /// Input normal uses model image axes (x right, y down, z away).
    /// The sign follows index-to-pinky crossed with wrist-to-middle.
    public static func classifyView(
        normalX: Double, normalZ: Double, handedness: Handedness
    ) -> ScanView? {
        guard normalX.isFinite, normalZ.isFinite else { return nil }
        let palmSign = handedness == .right ? -1.0 : 1.0
        let palmFacing = normalZ * palmSign
        if palmFacing >= 0.65 { return .palm }
        if palmFacing <= -0.65 { return .back }
        let thumbFacing = normalX * palmSign * (handedness == .right ? 1.0 : -1.0)
        if thumbFacing >= 0.65 { return .thumbSide }
        if thumbFacing <= -0.65 { return .pinkySide }
        return nil
    }
}
