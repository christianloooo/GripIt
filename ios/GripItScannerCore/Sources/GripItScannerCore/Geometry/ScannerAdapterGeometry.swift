import Foundation

/// Image orientation is analysis-only. The camera preview may mirror independently.
public enum SensorImageRotation: Equatable, Sendable {
    case up, down, left, right

    public init?(clockwiseDegrees: Double) {
        guard clockwiseDegrees.isFinite else { return nil }
        let normalized = clockwiseDegrees.truncatingRemainder(dividingBy: 360)
        switch (Int((normalized / 90).rounded()) % 4 + 4) % 4 {
        case 0: self = .up
        case 1: self = .right
        case 2: self = .down
        default: self = .left
        }
    }

    public func modelPoint(fromSensor point: PixelPoint) -> PixelPoint {
        switch self {
        case .up: point
        case .down: PixelPoint(x: 1 - point.x, y: 1 - point.y)
        case .left: PixelPoint(x: point.y, y: 1 - point.x)
        case .right: PixelPoint(x: 1 - point.y, y: point.x)
        }
    }

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
    /// Projects native sensor coordinates into a rotated, mirrored aspect-fill preview.
    public static func previewPoint(
        sensorPoint: PixelPoint, rotation: SensorImageRotation, mirrored: Bool,
        sourceWidth: Double, sourceHeight: Double, viewWidth: Double, viewHeight: Double
    ) -> PixelPoint? {
        guard [sensorPoint.x, sensorPoint.y, sourceWidth, sourceHeight, viewWidth, viewHeight].allSatisfy(\.isFinite),
              sourceWidth > 0, sourceHeight > 0, viewWidth > 0, viewHeight > 0 else { return nil }
        let rotated = rotation.modelPoint(fromSensor: sensorPoint)
        let swapsAxes = rotation == .left || rotation == .right
        let width = swapsAxes ? sourceHeight : sourceWidth
        let height = swapsAxes ? sourceWidth : sourceHeight
        let scale = max(viewWidth / width, viewHeight / height)
        return PixelPoint(
            x: (mirrored ? 1 - rotated.x : rotated.x) * width * scale + (viewWidth - width * scale) / 2,
            y: rotated.y * height * scale + (viewHeight - height * scale) / 2
        )
    }

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

    /// Side views are oblique captures. Fully edge-on poses hide the finger
    /// joints and cannot provide trustworthy measurements of all fingers.
    public static func matchesView(
        normalX: Double, normalZ: Double, handedness: Handedness, requested: ScanView
    ) -> Bool {
        guard normalX.isFinite, normalZ.isFinite else { return false }
        let palmFacing = normalZ * (handedness == .right ? -1.0 : 1.0)
        switch requested {
        case .palm: return palmFacing >= 0.65
        case .back: return palmFacing <= -0.65
        case .thumbSide: return normalX <= -0.45 && (0.25...0.90).contains(abs(normalZ))
        case .pinkySide: return normalX >= 0.45 && (0.25...0.90).contains(abs(normalZ))
        }
    }
}
