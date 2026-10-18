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

    /// A face counts as frontal at or above this cosine.
    public static let frontalFacing = 0.65
    /// A requested side view needs at least this much of the hand's radial axis
    /// aimed at the camera.
    public static let sideFacing = 0.45
    /// A requested side view must also keep at least this much palm or back in
    /// view. A fully edge-on silhouette hides the finger joints behind one
    /// another, so its segment lengths cannot be trusted.
    public static let sideObliqueFloor = 0.20
    /// Fingertips aimed down the lens foreshorten every segment, whichever face
    /// of the hand the camera nominally sees.
    public static let fingertipFacingLimit = 0.70

    /// Resolves the hand's own orthonormal basis and reports how much of each
    /// face points at the camera.
    ///
    /// `radial` runs pinkyMCP to indexMCP, `distal` runs wrist to middleMCP, both
    /// in the analysis image frame. Returns nil when the two axes are degenerate
    /// or parallel and define no basis.
    public static func handFacing(
        radial: Vector3D, distal: Vector3D, handedness: Handedness
    ) -> HandFacing? {
        guard let across = radial.unit, let along = distal.unit,
              let normal = across.cross(along).unit,
              let upward = normal.cross(across).unit
        else { return nil }
        // radial crossed with distal gives the outward palm normal for a right
        // hand and the inward one for a left hand, because the radial axis
        // reverses between the two. The camera lies toward negative z, so an axis
        // points at it exactly when its own z is negative.
        let outward = handedness == .right ? 1.0 : -1.0
        return HandFacing(
            palm: -outward * normal.z,
            thumb: -across.z,
            fingers: -upward.z
        )
    }

    /// The nearest canonical view, or nil when the hand sits between views.
    public static func classifyView(_ facing: HandFacing) -> ScanView? {
        guard [facing.palm, facing.thumb, facing.fingers].allSatisfy(\.isFinite) else { return nil }
        if facing.palm >= frontalFacing { return .palm }
        if facing.palm <= -frontalFacing { return .back }
        if facing.thumb >= frontalFacing { return .thumbSide }
        if facing.thumb <= -frontalFacing { return .pinkySide }
        return nil
    }

    /// Whether this pose is measurable for the view the scanner is asking for.
    /// Side views are deliberately oblique captures, wider than `classifyView`'s
    /// bands, because an oblique side still shows every finger joint.
    public static func matchesView(_ facing: HandFacing, requested: ScanView) -> Bool {
        guard [facing.palm, facing.thumb, facing.fingers].allSatisfy(\.isFinite) else { return false }
        guard abs(facing.fingers) <= fingertipFacingLimit else { return false }
        switch requested {
        case .palm: return facing.palm >= frontalFacing
        case .back: return facing.palm <= -frontalFacing
        case .thumbSide:
            return facing.thumb >= sideFacing && abs(facing.palm) >= sideObliqueFloor
        case .pinkySide:
            return facing.thumb <= -sideFacing && abs(facing.palm) >= sideObliqueFloor
        }
    }
}
