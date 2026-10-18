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
    var middleIDs: [GripFinger: Set<Int>] = [:]
    for finger in GripFinger.allCases {
      let ids = padIndices(hand: hand, finger: finger)
      let sampled = stride(from: 0, to: ids.count, by: max(1, ids.count / 90)).map { ids[$0] }
      padIDs[finger] = Set(sampled)
      selection.formUnion(sampled)
      if wrapsMiddle(finger, pitch: pitch) {
        let region = middleContactIndices(hand: hand, finger: finger)
        let middle = stride(from: 0, to: region.count, by: max(1, region.count / 60)).map {
          region[$0]
        }
        middleIDs[finger] = Set(middle)
        selection.formUnion(middle)
      }
    }
    let thumbBones = GripFinger.thumb.jointNames.compactMap { name in
      hand.joints.firstIndex { $0.name == name }
    }
    selection.formUnion(
      hand.vertices.indices.filter { i in
        i % 3 == 0 && thumbBones.reduce(0.0) { $0 + hand.weights[i][$1] } > 0.45
      })
    let ids = selection.sorted()
    let padOffsets = Dictionary(
      uniqueKeysWithValues: GripFinger.allCases.map { finger in
        (finger, ids.indices.filter { padIDs[finger]!.contains(ids[$0]) })
      })
    let middleOffsets = middleIDs.mapValues { region in
      ids.indices.filter { region.contains(ids[$0]) }
    }
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
      where finger.contact && !(pitch == .circleChange && finger.finger == .index) {
        let gaps = padOffsets[finger.finger]!.map {
          abs(simd_distance(skin[$0], center) - ballRadius)
        }.sorted().prefix(8)
        value += 65 * gaps.reduce(0) { $0 + $1 * $1 } / Double(max(1, gaps.count))
      }
      for offsets in middleOffsets.values {
        let gaps = offsets.map { abs(simd_distance(skin[$0], center) - ballRadius) }.sorted()
          .prefix(8)
        value += 45 * gaps.reduce(0) { $0 + $1 * $1 } / Double(max(1, gaps.count))
      }
      // A touching thumb at the side is not a supporting thumb. Fit the actual
      // fingerprint surface into the lower, central quadrant of the ball.
      let thumbPoints = padOffsets[.thumb]!.map { skin[$0] }.sorted {
        abs(simd_distance($0, center) - ballRadius) < abs(simd_distance($1, center) - ballRadius)
      }.prefix(12)
      let thumb = thumbPoints.reduce(SIMD3<Double>.zero, +) / Double(max(1, thumbPoints.count))
      let support = center + unit(SIMD3<Double>(0.10, -0.92, 0.38)) * ballRadius
      value += 14 * simd_length_squared(thumb - support)
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
              guard abs(candidate - original) <= (trial[i].finger == .thumb ? 1.2 : 0.45) else {
                continue
              }
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
