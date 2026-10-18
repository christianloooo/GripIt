import Foundation
import simd

/// Surface weights travel with the skinned mesh; they never create floating overlay objects.
public struct GripZoneSurface: Sendable {
  public let weights: [[Double]]
  /// Assessment wraps a named region around its finger so ball contact does not
  /// hide the finding. Contact/effort masks and picking remain unchanged.
  public let feedbackWeights: [[Double]]
  public let picking: [GripZoneID?]
  public static let zones = GripZoneID.allCases

  public init(pose: GripPose, gripPlan: GripPlan, hand: GripHandAsset) {
    let applicable = Set(gripPlan.zones.map(\.zoneId))
    let rest = Dictionary(uniqueKeysWithValues: hand.joints.map { ($0.name, gv($0.position)) })
    func smooth(_ x: Double) -> Double {
      let t = min(1, max(0, x))
      return t * t * (3 - 2 * t)
    }
    var weights: [[Double]] = []
    var feedbackWeights: [[Double]] = []
    var picking: [GripZoneID?] = []
    for i in pose.vertices.indices {
      let source = gv(hand.vertices[i])
      var w = Array(repeating: 0.0, count: Self.zones.count)
      var feedback = w
      var owner: GripZoneID?
      var dominance = 0.35
      for zone in gripPlan.zones {
        guard let finger = zone.zoneId.finger,
          let rig = pose.fingers.first(where: { $0.finger == finger })
        else { continue }
        let joints = finger.jointNames.compactMap { name in
          hand.joints.firstIndex { $0.name == name }
        }
        // Thumb CMC weights extend into the thenar palm. Do not call the entire palm a thumb pad.
        let influence = joints.dropFirst(finger == .thumb ? 1 : 0).reduce(0.0) {
          $0 + hand.weights[i][$1]
        }
        if influence > dominance {
          owner = zone.zoneId
          dominance = influence
        }
        let side = zone.placement?.surface == .side || zone.zoneId == .pinky
        let start = rest[finger.jointNames[side ? 1 : 2]]!
        let end = rest[finger.jointNames[3]]!
        let axis = unit(end - start)
        let along = simd_dot(source - start, axis) / simd_length(end - start)
        let taper = smooth((along + (side ? 0.15 : 0.05)) / 0.5)
        let a = rig.points[side ? 1 : 2]
        let b = rig.points[3]
        let t = min(1, max(0, simd_dot(pose.vertices[i] - a, b - a) / simd_length_squared(b - a)))
        let centerline = a + (b - a) * t
        let outward = unit(pose.vertices[i] - centerline)
        var contactCenter = pose.ballCenter
        if zone.placement?.region == .thumbSide,
          let opposingZone = zone.placement?.opposes.first,
          let other = pose.fingers.first(where: { $0.finger == opposingZone.finger })
        {
          // The circle-change loop meets another pad rather than the baseball.
          let direction = unit(other.points[3] - other.points[2])
          contactCenter = other.points[3] - direction * min(other.radius, other.lengths[2] * 0.45)
        }
        let towardContact = unit(contactCenter - centerline)
        let facing = smooth((simd_dot(outward, towardContact) + 0.25) / 0.85)
        let index = Self.zones.firstIndex(of: zone.zoneId)!
        let region = smooth((influence - 0.35) / 0.5) * taper
        w[index] = region * facing
        // Display coverage reaches the middle of the finger and wraps its
        // circumference. This is a visual fade, never a coaching threshold.
        let feedbackStart = rest[finger.jointNames[1]]!
        let feedbackAxis = unit(end - feedbackStart)
        let feedbackAlong = simd_dot(source - feedbackStart, feedbackAxis)
          / simd_length(end - feedbackStart)
        let broadTaper = smooth((feedbackAlong + 0.12) / 0.48)
        feedback[index] = smooth((influence - 0.35) / 0.5) * broadTaper
      }
      if owner == nil {
        if source.y < 14 {
          if applicable.contains(.wrist) { owner = .wrist }
        } else if source.y < 78, applicable.contains(.palm) {
          owner = .palm
        }
      }
      if applicable.contains(.wrist) {
        w[Self.zones.firstIndex(of: .wrist)!] = 0.85 * (1 - smooth((source.y - 2) / 14))
      }
      if applicable.contains(.palm), owner == .palm {
        w[Self.zones.firstIndex(of: .palm)!] =
          smooth((source.y - 16) / 12) * (1 - smooth((source.y - 55) / 20))
          * smooth((source.z - 1) / 9) * (1 - smooth((abs(source.x) - 20) / 18))
      }
      for zone in [GripZoneID.palm, .wrist] {
        let index = Self.zones.firstIndex(of: zone)!
        feedback[index] = w[index]
      }
      weights.append(w)
      feedbackWeights.append(feedback)
      picking.append(owner)
    }
    self.weights = weights
    self.feedbackWeights = feedbackWeights
    self.picking = picking
  }
  /// Face vertices use their actual barycentric contribution. The baseball blocks taps naturally.
  public func zone(face: Int, barycentric: SIMD3<Double>, indices: [UInt32]) -> GripZoneID? {
    guard face >= 0, face * 3 + 2 < indices.count else { return nil }
    var votes: [GripZoneID: Double] = [:]
    for corner in 0..<3 {
      let index = Int(indices[face * 3 + corner])
      if picking.indices.contains(index), let zone = picking[index] {
        votes[zone, default: 0] += barycentric[corner]
      }
    }
    return votes.max { $0.value < $1.value }.flatMap { $0.value >= 0.45 ? $0.key : nil }
  }
}
