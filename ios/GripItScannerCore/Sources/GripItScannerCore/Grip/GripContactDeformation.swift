import simd

extension GripPoseSolver {
  static func pressureAmount(_ pressure: GripPressure) -> Double {
    switch pressure {
    case .none: 0
    case .light: 0.3
    case .medium: 0.65
    case .firm: 1
    }
  }
  /// Illustrative blanching accompanies compression, independent of diagnostic
  /// severity colors. Only palmar skin close to the ball carries this cue.
  public static func contactPressureWeights(hand: GripHandAsset, pose: GripPose) -> [Double] {
    var weights = Array(repeating: 0.0, count: pose.vertices.count)
    for zone in pose.pitch.zoneTemplates {
      guard zone.placement?.surface == .pad, let f = zone.zoneId.finger,
        let pressure = zone.pressure,
        !(pose.pitch == .circleChange && [.index, .thumb].contains(f))
      else { continue }
      for i in padIndices(hand: hand, finger: f) {
        let gap = abs(simd_distance(pose.vertices[i], pose.ballCenter) - ballRadius)
        weights[i] = pressureAmount(pressure) * pow(max(0, 1 - gap / 2.5), 2)
      }
    }
    return weights
  }
  /// A bounded visual approximation of compliant fingertip skin, driven by the
  /// guide's qualitative pressure. This is not force inferred from a scan/photo.
  /// The rig must already touch: this pass cannot bridge a floating finger.
  static func compressContacts(
    hand: GripHandAsset, vertices: [SIMD3<Double>], fingers: [GripFingerPose],
    center: SIMD3<Double>, pitch: PitchGrip
  ) -> [SIMD3<Double>] {
    var result = vertices
    for zone in pitch.zoneTemplates {
      guard zone.placement?.surface == .pad, let f = zone.zoneId.finger,
        let rig = fingers.first(where: { $0.finger == f }), let pressure = zone.pressure,
        !(pitch == .circleChange && [.index, .thumb].contains(f))
      else { continue }
      let amount = pressureAmount(pressure)
      guard amount > 0 else { continue }
      let ids = padIndices(hand: hand, finger: f)
      let contact = skinContact(hand: hand, vertices: vertices, finger: f, center: center)
      guard abs(simd_distance(contact, center) - ballRadius) < 1.5 else { continue }
      let n = unit(contact - center)
      let along = unit(rig.points[3] - rig.points[2])
      let across = unit(simd_cross(along, n))
      let tangent = unit(simd_cross(n, across))
      let width = max(4, rig.radius * 0.85)
      for i in ids {
        let original = vertices[i]
        let delta = original - contact
        let x = simd_dot(delta, across)
        let y = simd_dot(delta, tangent)
        let radius = (x * x / (width * width) + y * y / 81)
        let gap = simd_distance(original, center) - ballRadius
        guard radius < 1.8, gap < 3, gap > -1.2 else { continue }
        let falloff = pow(max(0, 1 - radius / 1.8), 2)
        // Spread compliant flesh laterally, retaining the authored nail side
        // and skeleton. The central pad follows the ball's curved surface.
        var point = original + across * (x * 0.10 * amount * falloff)
        let distance = simd_distance(point, center)
        let flatten = min(1, max(0, 1 - radius)) * amount
        let correction = min(1.1, max(-1.1, ballRadius + 0.06 - distance))
        point += unit(point - center) * (correction * flatten)
        // Never introduce overlap while spreading an already fitted pad.
        if simd_distance(point, center) < ballRadius + 0.025 {
          point = center + unit(point - center) * (ballRadius + 0.025)
        }
        let move = point - original
        result[i] = original + move * min(1, 1.2 / max(1e-9, simd_length(move)))
      }
    }
    return result
  }
}
