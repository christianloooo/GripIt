import Foundation
import simd

extension GripPoseSolver {
  /// Refine the real authored skin, not just idealized finger capsules. Joint
  /// changes remain near the kinematic solution; skin vertices are never pushed
  /// onto the sphere or sculpted to conceal a collision.
  static func fitAuthoredSurface(
    hand: GripHandAsset, fingers initial: [GripFingerPose], scale: SIMD3<Double>,
    center initialCenter: SIMD3<Double>, pitch: PitchGrip
  ) throws -> (fingers: [GripFingerPose], center: SIMD3<Double>) {
    var selection = Set(
      stride(from: 0, to: hand.vertices.count, by: max(1, hand.vertices.count / 1400)))
    var padIDs: [GripFinger: Set<Int>] = [:]
    for finger in GripFinger.allCases {
      let ids = padIndices(hand: hand, finger: finger)
      let sampled = stride(from: 0, to: ids.count, by: max(1, ids.count / 90)).map { ids[$0] }
      padIDs[finger] = Set(sampled)
      selection.formUnion(sampled)
    }
    let ids = selection.sorted()
    let padOffsets = Dictionary(
      uniqueKeysWithValues: GripFinger.allCases.map { finger in
        (finger, ids.indices.filter { padIDs[finger]!.contains(ids[$0]) })
      })
    func score(_ fingers: [GripFingerPose], _ center: SIMD3<Double>) throws -> Double {
      let skin = try deform(
        hand: hand, fingers: fingers, scale: scale, center: center, vertexIndices: ids)
      var maximum = 0.0
      var collisions = 0.0
      for point in skin {
        let overlap = max(0, ballRadius - simd_distance(point, center))
        maximum = max(maximum, overlap)
        collisions += overlap * overlap
      }
      var value = 700 * maximum * maximum + collisions * 0.6
      for finger in fingers
      where finger.contact && !(pitch == .circleChange && [.thumb, .index].contains(finger.finger))
      {
        let gaps = padOffsets[finger.finger]!.map {
          abs(simd_distance(skin[$0], center) - ballRadius)
        }.sorted().prefix(8)
        value += 65 * gaps.reduce(0) { $0 + $1 * $1 } / Double(max(1, gaps.count))
      }
      if pitch == .circleChange {
        var gap = Double.infinity
        for a in padOffsets[.index]! {
          for b in padOffsets[.thumb]! {
            gap = min(gap, simd_distance(skin[a], skin[b]))
          }
        }
        value += 80 * gap * gap
      }
      // Capsule clearance and synthetic bone-tip targets belong to the coarse
      // initializer. Retaining them here fights real skin contact and creates
      // floating pads. Only a small pose regularizer accompanies skin fitting.
      for i in fingers.indices {
        for j in 0..<3 {
          value += 0.5 * pow(fingers[i].angles[j] - initial[i].angles[j], 2)
        }
      }
      value += simd_length_squared(center - initialCenter) * 0.05
      return value
    }
    var fingers = initial
    var center = initialCenter
    var best = try score(fingers, center)
    for (step, ballStep) in [(0.12, 3.0), (0.05, 1.5), (0.02, 0.6), (0.008, 0.2)] {
      for _ in 0..<4 {
        try Task.checkCancellation()
        for axis in 0..<3 {
          for sign in [-1.0, 1.0] {
            var candidate = center
            candidate[axis] += sign * ballStep
            guard simd_distance(candidate, initialCenter) < 18 else { continue }
            var trial = fingers
            for i in trial.indices {
              trial[i].target += candidate - center
              update(&trial[i], center: candidate)
            }
            let value = try score(trial, candidate)
            if value < best {
              center = candidate
              fingers = trial
              best = value
            }
          }
        }
        for i in fingers.indices {
          for axis in 0..<5 {
            for sign in [-1.0, 1.0] {
              var trial = fingers
              let current =
                axis < 3
                ? fingers[i].angles[axis] : axis == 3 ? fingers[i].yaw : fingers[i].opposition
              let original =
                axis < 3
                ? initial[i].angles[axis] : axis == 3 ? initial[i].yaw : initial[i].opposition
              let candidate = current + sign * step
              guard abs(candidate - original) <= 0.45 else { continue }
              if axis < 3 {
                let minimum = axis == 0 ? (trial[i].finger == .thumb ? 0.1 : -0.35) : 0
                let maximum =
                  trial[i].finger == .thumb ? [1.1, 1.5, 1.4][axis] : [1.5, 1.85, 1.7][axis]
                guard (minimum...maximum).contains(candidate) else { continue }
                trial[i].angles[axis] = candidate
              } else if axis == 3 {
                guard (trial[i].finger == .thumb ? 0.1...2.2 : -0.7...0.7).contains(candidate)
                else { continue }
                trial[i].yaw = candidate
              } else {
                let limits =
                  trial[i].allowsOpposition
                  ? (trial[i].finger == .thumb ? 0.0...1.35 : -1.35...1.35) : -0.15...0.15
                guard limits.contains(candidate) else { continue }
                trial[i].opposition = candidate
              }
              update(&trial[i], center: center)
              let value = try score(trial, center)
              if value < best {
                fingers = trial
                best = value
              }
            }
          }
        }
      }
    }
    return (fingers, center)
  }
}
