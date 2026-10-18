import Foundation

/// A direction in the analysis image frame: x right, y down, z away from the camera.
/// The camera therefore sits toward negative z.
public struct Vector3D: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static func - (left: Vector3D, right: Vector3D) -> Vector3D {
        Vector3D(x: left.x - right.x, y: left.y - right.y, z: left.z - right.z)
    }

    func cross(_ other: Vector3D) -> Vector3D {
        Vector3D(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    /// Nil for a zero-length or non-finite direction, which carries no orientation.
    var unit: Vector3D? {
        let length = (x * x + y * y + z * z).squareRoot()
        guard length.isFinite, length > 0.000_001 else { return nil }
        return Vector3D(x: x / length, y: y / length, z: z / length)
    }
}

/// How much of each face of the hand points at the camera. Every component is a
/// cosine in `-1 ... 1`.
///
/// The components are projections of the hand's *own* orthonormal axes onto the
/// direction of the camera, not components of a normal expressed in image axes.
/// That distinction is the whole point: rotating the hand within the image plane
/// — a roll about the camera's optical axis — redistributes a normal's x and y
/// components while leaving the camera's view of the hand completely unchanged.
/// Reading a side view off the normal's x component therefore made the decision
/// depend on wrist tilt and on whether the analysis buffer happened to be
/// upright, neither of which changes what the camera can measure. These three
/// cosines are invariant under that roll by construction.
public struct HandFacing: Equatable, Sendable {
    /// `+1` when the palm points straight at the camera, `-1` for the back of the hand.
    public let palm: Double
    /// `+1` when the thumb side points straight at the camera, `-1` for the pinky side.
    public let thumb: Double
    /// `+1` when the fingertips point straight down the lens, which foreshortens
    /// every finger and makes segment lengths unmeasurable.
    public let fingers: Double

    public init(palm: Double, thumb: Double, fingers: Double) {
        self.palm = palm
        self.thumb = thumb
        self.fingers = fingers
    }
}
