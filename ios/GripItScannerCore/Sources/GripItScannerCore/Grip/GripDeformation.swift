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
          radialScale: rig.radius
            / (hand.authoredFingerRadii?[rig.finger.rawValue]
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
        let fraction =
          map.thumbBase && hand.preserveAuthoredAnatomy != true
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
    padIndices(hand: hand, finger: finger).map { vertices[$0] }
  }
  /// Fingerprint skin only. A dorsal vertex or a fingertip's side touching the
  /// sphere is not evidence that the fleshy pad is holding the ball.
  static func padIndices(hand: GripHandAsset, finger: GripFinger) -> [Int] {
    let a = hand.joints.firstIndex { $0.name == finger.jointNames[2] }!
    let b = hand.joints.firstIndex { $0.name == finger.jointNames[3] }!
    let start = gv(hand.joints[a].position)
    let end = gv(hand.joints[b].position)
    let direction = unit(end - start)
    let palmar = unit(SIMD3<Double>(0, 0, 1) - direction * direction.z)
    return hand.vertices.indices.compactMap { i in
      let offset = gv(hand.vertices[i]) - start
      let along = simd_dot(offset, direction) / simd_distance(start, end)
      // The thumb's fleshy pad wraps over its rounded end. Excluding the
      // final 10% discarded a genuine support contact in the reference grip.
      // The palmar half-space still excludes the nail and dorsal cap.
      let upperBound = finger == .thumb ? 0.98 : 0.90
      return hand.weights[i][a] + hand.weights[i][b] > 0.6
        && (0.18...upperBound).contains(along) && simd_dot(offset, palmar) > 0
        ? i : nil
    }
  }
  public static func skinContact(
    hand: GripHandAsset, vertices: [SIMD3<Double>],
    finger: GripFinger, center: SIMD3<Double>
  ) -> SIMD3<Double> {
    let closest = padVertices(hand: hand, vertices: vertices, finger: finger)
      .sorted {
        abs(simd_distance($0, center) - ballRadius) < abs(simd_distance($1, center) - ballRadius)
      }
      .prefix(12)
    return closest.reduce(.zero, +) / Double(max(1, closest.count))
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
    rotation: simd_quatd, hand: GripHandAsset, vertices: [SIMD3<Double>]
  ) -> [GripSeamFit] {
    let relations = Dictionary(
      uniqueKeysWithValues: pitch.zoneTemplates.compactMap { zone in
        zone.zoneId.finger.map { ($0, zone.placement?.seam ?? .none) }
      })
    return fingers.filter { pitch.upperContacts.contains($0.finger) }.map { finger in
      let normal = unit(
        skinContact(hand: hand, vertices: vertices, finger: finger.finger, center: center) - center)
      let local = rotation.inverse.act(normal * ballRadius)
      let ids = GripSeamTemplate.samples(ball, pitch: pitch, finger: finger.finger)
      let seam = ball.seams[
        ids.min {
          simd_distance(gv(ball.seams[$0].position), local)
            < simd_distance(gv(ball.seams[$1].position), local)
        }!]
      let direction = unit(finger.points[3] - finger.points[2])
      let tangent = unit(direction - normal * simd_dot(direction, normal))
      return GripSeamFit(
        finger: finger.finger, distanceMm: simd_distance(gv(seam.position), local),
        tangentAlignment: abs(simd_dot(tangent, rotation.act(gv(seam.tangent)))),
        across: relations[finger.finger] == .across, leather: relations[finger.finger] == .beside)
    }
  }
  static func orientBall(
    _ ball: GripBallAsset, pitch: PitchGrip, fingers: [GripFingerPose], center: SIMD3<Double>,
    hand: GripHandAsset, vertices: [SIMD3<Double>]
  ) -> simd_quatd {
    let contacts = fingers.filter { pitch.upperContacts.contains($0.finger) }
    let relations = Dictionary(
      uniqueKeysWithValues: pitch.zoneTemplates.compactMap { zone in
        zone.zoneId.finger.map { ($0, zone.placement?.seam ?? .none) }
      })
    let patches = Dictionary(
      uniqueKeysWithValues: contacts.map {
        ($0.finger, GripSeamTemplate.samples(ball, pitch: pitch, finger: $0.finger))
      })
    let contactNormals = Dictionary(
      uniqueKeysWithValues: contacts.map {
        (
          $0.finger,
          unit(
            skinContact(hand: hand, vertices: vertices, finger: $0.finger, center: center) - center)
        )
      })
    let positions = ball.seams.map { gv($0.position) }
    let tangents = ball.seams.map { gv($0.tangent) }
    // Construct the ball frame from the assigned stitching and real contacts.
    // This follows a deeper grip without jumping to another seam or retaining
    // an unrelated world-space ball rotation from the old pose.
    func frame(_ normal: SIMD3<Double>, _ tangent: SIMD3<Double>) -> simd_double3x3 {
      let x = unit(tangent - normal * simd_dot(tangent, normal))
      return simd_double3x3(columns: (x, unit(simd_cross(normal, x)), normal))
    }
    let anchored = contacts.filter { GripSeamTemplate.anchor(pitch, $0.finger) != nil }
    let reference: simd_quatd
    if anchored.count == 2 {
      let a = unit(GripSeamTemplate.anchor(pitch, anchored[0].finger)!)
      let b = unit(GripSeamTemplate.anchor(pitch, anchored[1].finger)!)
      let c = contactNormals[anchored[0].finger]!
      let d = contactNormals[anchored[1].finger]!
      reference = simd_quatd(frame(unit(c + d), d - c) * frame(unit(a + b), b - a).transpose)
    } else {
      let f = anchored[0]
      let anchor = GripSeamTemplate.anchor(pitch, f.finger)!
      let seam = ball.seams.min {
        simd_distance(gv($0.position), anchor) < simd_distance(gv($1.position), anchor)
      }!
      let normal = contactNormals[f.finger]!
      var tangent = unit(f.points[3] - f.points[2])
      if simd_dot(GripSeamTemplate.reference(pitch).act(gv(seam.tangent)), tangent) < 0 {
        tangent = -tangent
      }
      reference = simd_quatd(
        frame(normal, tangent) * frame(unit(anchor), gv(seam.tangent)).transpose)
    }
    func rotation(_ angles: SIMD3<Double>) -> simd_quatd {
      simd_quatd(angle: angles.z, axis: SIMD3(0, 0, 1))
        * simd_quatd(angle: angles.y, axis: SIMD3(0, 1, 0))
        * simd_quatd(angle: angles.x, axis: SIMD3(1, 0, 0)) * reference
    }
    func score(_ angles: SIMD3<Double>) -> Double {
      let q = rotation(angles)
      let inverse = q.inverse
      return contacts.reduce(0) { value, finger in
        let normal = contactNormals[finger.finger]!
        let pad = normal * ballRadius
        let local = inverse.act(pad)
        var nearest = Double.infinity
        var index = 0
        for i in patches[finger.finger]! {
          let d = simd_length_squared(positions[i] - local)
          if d < nearest {
            nearest = d
            index = i
          }
        }
        if relations[finger.finger] == .beside {
          return value + 4 * pow(sqrt(nearest) - 7, 2)
        }
        let direction = unit(finger.points[3] - finger.points[2])
        let tangent = unit(direction - normal * simd_dot(direction, normal))
        let dot = simd_dot(tangent, q.act(tangents[index]))
        return value + nearest * 2 + 140
          * (relations[finger.finger] == .across ? dot * dot : 1 - dot * dot)
      }
    }
    var best = SIMD3<Double>.zero
    var bestScore = score(best)
    for step in [0.16, 0.06, 0.02, 0.006] {
      for _ in 0..<3 {
        for axis in 0..<3 {
          for sign in [-1.0, 1.0] {
            var candidate = best
            candidate[axis] += step * sign
            guard simd_length(candidate) < 0.65 else { continue }
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
