import Foundation

public struct PixelPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct CameraIntrinsics: Equatable, Sendable {
    public let fx: Double
    public let fy: Double
    public let cx: Double
    public let cy: Double

    public init(fx: Double, fy: Double, cx: Double, cy: Double) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
    }
}

public struct MetricPoint3D: Codable, Equatable, Sendable {
    public let xMm: Double
    public let yMm: Double
    public let zMm: Double

    public init(xMm: Double, yMm: Double, zMm: Double) {
        self.xMm = xMm
        self.yMm = yMm
        self.zMm = zMm
    }

    public func distance(to other: MetricPoint3D) -> Double {
        let dx = xMm - other.xMm
        let dy = yMm - other.yMm
        let dz = zMm - other.zMm
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }
}

public enum DepthProjectionError: Error, Equatable, Sendable {
    case nonFiniteInput
    case invalidFocalLength
    case depthOutOfRange(Double)
}

public enum DepthProjector {
    public static let supportedDepthRangeMeters = 0.12 ... 1.2

    public static func project(
        pixel: PixelPoint,
        depthMeters: Double,
        intrinsics: CameraIntrinsics
    ) throws -> MetricPoint3D {
        let values = [pixel.x, pixel.y, depthMeters, intrinsics.fx, intrinsics.fy, intrinsics.cx, intrinsics.cy]
        guard values.allSatisfy(\.isFinite) else {
            throw DepthProjectionError.nonFiniteInput
        }
        guard intrinsics.fx > 0, intrinsics.fy > 0 else {
            throw DepthProjectionError.invalidFocalLength
        }
        guard supportedDepthRangeMeters.contains(depthMeters) else {
            throw DepthProjectionError.depthOutOfRange(depthMeters)
        }

        let xMeters = (pixel.x - intrinsics.cx) * depthMeters / intrinsics.fx
        let yMeters = (pixel.y - intrinsics.cy) * depthMeters / intrinsics.fy
        return MetricPoint3D(
            xMm: xMeters * 1_000,
            yMm: yMeters * 1_000,
            zMm: depthMeters * 1_000
        )
    }
}

public enum HandCanonicalizer {
    public static func canonicalize(
        _ point: MetricPoint3D,
        handedness: Handedness
    ) -> MetricPoint3D {
        guard handedness == .left else { return point }
        return MetricPoint3D(xMm: -point.xMm, yMm: point.yMm, zMm: point.zMm)
    }

    public static func canonicalize(
        _ points: [String: MetricPoint3D],
        handedness: Handedness
    ) -> [String: MetricPoint3D] {
        points.mapValues { canonicalize($0, handedness: handedness) }
    }
}
