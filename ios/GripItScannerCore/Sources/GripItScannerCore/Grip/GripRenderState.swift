import Foundation

/// Everything the renderer derives from one solved pose, built once.
///
/// The pose itself was already cached per pitch, but the data the scene needs on
/// top of it was not. Rebuilding the zone surface costs roughly 180 ms for the
/// supplied 35k-vertex rig and the shading weights another 13 ms, and both ran on
/// the main thread while the view updated. Switching pitch paid that again every
/// time, including switching back to a grip already on screen once.
///
/// Holding them beside the pose lets the same cache that already keeps the solve
/// keep these too, on the task that solved it rather than on the main thread.
public struct GripRenderState: Sendable {
  public let pose: GripPose
  public let plan: GripPlan
  public let surface: GripZoneSurface
  /// Illustrative prescribed pressure per mesh vertex. Not measured finger force.
  public let pressureWeights: [Double]

  public init(pose: GripPose, hand: GripHandAsset) {
    self.pose = pose
    let plan = GripPlan(pose: pose)
    self.plan = plan
    surface = GripZoneSurface(pose: pose, gripPlan: plan, hand: hand)
    pressureWeights = GripPoseSolver.pressureShadingWeights(hand: hand, pose: pose)
  }

  public init(pose: GripPose) throws {
    self.init(pose: pose, hand: try GripHandAsset.load())
  }
}
