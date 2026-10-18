import Foundation
import simd

extension GripPoseSolver {
  static func deform(
    hand: GripHandAsset, fingers: [GripFingerPose], scale: SIMD3<Double>, center: SIMD3<Double>,
    vertexIndices: [Int]? = nil
  ) throws -> [SIMD3<Double>] {
    struct BoneMap {
      let source: SIMD3<Double>
      let open: SIMD3<Double>
      let direction: SIMD3<Double>
      let axialScale: Double
      let radialScale: Double
      let real: simd_quatd
      let dual: simd_quatd
      let thumbBase: Bool
      let proximalFinger: Bool
    }
    let joints = hand.joints.map { gv($0.position) }
    var maps = [Int: BoneMap]()
    for rig in fingers {
      let ids = rig.finger.jointNames.map { name in hand.joints.firstIndex { $0.name == name }! }
      var open = [rig.points[0]]
      for j in 0..<3 {
        open.append(open[j] + unit(joints[ids[j + 1]] - joints[ids[j]]) * rig.lengths[j])
      }
      for j in 0..<4 {
        let segment = min(j, 2)
        let a = joints[ids[segment]]
        let b = joints[ids[segment + 1]]
        let direction = unit(b - a)
        let q = simd_quatd(from: direction, to: unit(rig.points[segment + 1] - rig.points[segment]))
        let translation = rig.points[j] - q.act(open[j])
        let dual = simd_quatd(
          vector: (simd_quatd(ix: translation.x, iy: translation.y, iz: translation.z, r: 0) * q)
            .vector * 0.5)
        maps[ids[j]] = BoneMap(
          source: joints[ids[j]], open: open[j], direction: direction,
          axialScale: rig.lengths[segment] / simd_distance(a, b),
          radialScale: rig.radius / (hand.authoredFingerRadii?[rig.finger.rawValue]
            ?? (rig.finger == .thumb ? 10 : rig.finger == .pinky ? 6.5 : 8.5)),
          real: q, dual: dual, thumbBase: rig.finger == .thumb && j == 0,
          proximalFinger: rig.finger != .thumb && j == 0)
      }
    }
    return try (vertexIndices ?? Array(hand.vertices.indices)).map { i in
      if i % 512 == 0 { try Task.checkCancellation() }
      let source = hand.vertices[i]
      let original = gv(source)
      let palm = original * scale
      var bind = SIMD3<Double>.zero
      var real = SIMD4<Double>.zero
      var dual = SIMD4<Double>.zero
      let reference = SIMD4<Double>(0, 0, 0, 1)
      var identityWeight = 0.0
      for j in hand.joints.indices {
        let sourceWeight = hand.weights[i][j]
        guard sourceWeight > 1e-8 else { continue }
        guard let map = maps[j] else {
          bind += palm * sourceWeight
          identityWeight += sourceWeight
          continue
        }
        let offset = original - map.source
        let axial = map.direction * simd_dot(offset, map.direction)
        var radial = offset - axial
        let bindRadialDistance = simd_length(radial)
        if map.proximalFinger || map.thumbBase {
          // Blend palm depth into finger thickness at the MCP. Applying the
          // full finger radius scale to the broad palmar pad made a raised
          // ridge/sheet across the knuckles after personalizing a thin palm.
          let t = max(0, min(1, simd_dot(offset, map.direction) / (map.thumbBase ? 28 : 18)))
          let blend = t * t * (3 - 2 * t)
          radial.z *= (scale.z / map.radialScale) * (1 - blend) + blend
        }
        let fraction = map.thumbBase && hand.preserveAuthoredAnatomy != true
          ? max(0, min(1, (bindRadialDistance - 14) / 16)) : 0
        let palmShare = fraction * fraction * (3 - 2 * fraction)
        let weight = sourceWeight * (1 - palmShare)
        bind +=
          (map.open + axial * map.axialScale + radial * map.radialScale) * weight + palm
          * (sourceWeight * palmShare)
        identityWeight += sourceWeight * palmShare
        // Align quaternion hemispheres before blending. DQ blending keeps a
        // bent thumb's cross section from collapsing into a flat LBS plate.
        let sign = simd_dot(map.real.vector, reference) < 0 ? -1.0 : 1.0
        real += map.real.vector * (weight * sign)
        dual += map.dual.vector * (weight * sign)
      }
      real += reference * identityWeight
      let norm = max(1e-9, simd_length(real))
      real /= norm
      dual /= norm
      dual -= real * simd_dot(real, dual)
      let q = simd_quatd(vector: real)
      let translation = (simd_quatd(vector: dual) * q.conjugate).imag * 2
      return q.act(bind) + translation
    }
  }
  static func padVertices(hand: GripHandAsset, vertices: [SIMD3<Double>], finger: GripFinger)
    -> [SIMD3<Double>]
  {
    let a = hand.joints.firstIndex { $0.name == finger.jointNames[2] }!
    let b = hand.joints.firstIndex { $0.name == finger.jointNames[3] }!
    let start = gv(hand.joints[a].position)
    let end = gv(hand.joints[b].position)
    let direction = unit(end - start)
    return hand.vertices.indices.compactMap { i in
      hand.weights[i][a] + hand.weights[i][b] > 0.6
        && simd_dot(gv(hand.vertices[i]) - start, direction) > simd_distance(start, end) * 0.35
        ? vertices[i] : nil
    }
  }
  static func padGap(
    hand: GripHandAsset, vertices: [SIMD3<Double>], first: GripFinger, second: GripFinger
  ) -> Double {
    let a = padVertices(hand: hand, vertices: vertices, finger: first)
    let b = padVertices(hand: hand, vertices: vertices, finger: second)
    var distance = Double.infinity
    for p in a { for q in b { distance = min(distance, simd_distance(p, q)) } }
    return distance
  }
  static func inspectSeams(
    _ ball: GripBallAsset, pitch: PitchGrip, fingers: [GripFingerPose], center: SIMD3<Double>,
    rotation: simd_quatd
  ) -> [GripSeamFit] {
    let relations = Dictionary(
      uniqueKeysWithValues: pitch.zoneTemplates.compactMap { zone in
        zone.zoneId.finger.map { ($0, zone.placement?.seam ?? .none) }
      })
    return fingers.filter { pitch.upperContacts.contains($0.finger) }.map { finger in
      let normal = unit(finger.points[3] - center)
      let local = rotation.inverse.act(normal * ballRadius)
      let seam = ball.seams.min {
        simd_distance(gv($0.position), local) < simd_distance(gv($1.position), local)
      }!
      let direction = unit(finger.points[3] - finger.points[2])
      let tangent = unit(direction - normal * simd_dot(direction, normal))
      return GripSeamFit(
        finger: finger.finger, distanceMm: simd_distance(gv(seam.position), local),
        tangentAlignment: abs(simd_dot(tangent, rotation.act(gv(seam.tangent)))),
        across: relations[finger.finger] == .across, leather: relations[finger.finger] == .beside)
    }
  }
  static func orientBall(
    _ ball: GripBallAsset, pitch: PitchGrip, fingers: [GripFingerPose], center: SIMD3<Double>
  ) -> simd_quatd {
    let contacts = fingers.filter { pitch.upperContacts.contains($0.finger) }
    let relations = Dictionary(
      uniqueKeysWithValues: pitch.zoneTemplates.compactMap { zone in
        zone.zoneId.finger.map { ($0, zone.placement?.seam ?? .none) }
      })
    func rotation(_ angles: SIMD3<Double>) -> simd_quatd {
      simd_quatd(angle: angles.z, axis: SIMD3(0, 0, 1))
        * simd_quatd(angle: angles.y, axis: SIMD3(0, 1, 0))
        * simd_quatd(angle: angles.x, axis: SIMD3(1, 0, 0))
    }
    let positions = ball.seams.map { gv($0.position) }
    let tangents = ball.seams.map { gv($0.tangent) }
    func score(_ angles: SIMD3<Double>) -> Double {
      let q = rotation(angles)
      let inverse = q.inverse
      return contacts.reduce(0) { value, finger in
        let normal = unit(finger.points[3] - center)
        let pad = normal * ballRadius
        let local = inverse.act(pad)
        var nearest = Double.infinity
        var index = 0
        for i in positions.indices {
          let d = simd_length_squared(positions[i] - local)
          if d < nearest {
            nearest = d
            index = i
          }
        }
        if relations[finger.finger] == .beside {
          return value + 12 * pow(max(0, 4 - sqrt(nearest)), 2)
        }
        let direction = unit(finger.points[3] - finger.points[2])
        let tangent = unit(direction - normal * simd_dot(direction, normal))
        let dot = simd_dot(tangent, q.act(tangents[index]))
        return value + nearest * 2 + 140
          * (relations[finger.finger] == .across ? dot * dot : 1 - dot * dot)
      }
    }
    var best = SIMD3<Double>.zero
    var bestScore = Double.infinity
    for x in 0..<8 {
      for y in 0..<8 {
        for z in 0..<8 {
          let angles = SIMD3(Double(x), Double(y), Double(z)) * (.pi / 4)
          let value = score(angles)
          if value < bestScore {
            best = angles
            bestScore = value
          }
        }
      }
    }
    for step in [0.3, 0.12, 0.04] {
      for _ in 0..<3 {
        for axis in 0..<3 {
          for sign in [-1.0, 1.0] {
            var candidate = best
            candidate[axis] += step * sign
            let value = score(candidate)
            if value < bestScore {
              best = candidate
              bestScore = value
            }
          }
        }
      }
    }
    return rotation(best)
  }
}
