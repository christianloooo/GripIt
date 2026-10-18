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
        !(pose.pitch == .circleChange && f == .index)
      else { continue }
      for i in contactIndices(hand: hand, finger: f, pitch: pose.pitch) {
        let gap = abs(simd_distance(pose.vertices[i], pose.ballCenter) - ballRadius)
        weights[i] = pressureAmount(pressure) * pow(max(0, 1 - gap / 2.5), 2)
      }
    }
    return weights
  }
  /// The demo effort map covers every instructed surface, including support
  /// and wrist stabilization. Actual compression retains its contact-only mask.
  public static func pressureShadingWeights(
    hand: GripHandAsset, pose: GripPose, plan suppliedPlan: GripPlan? = nil
  ) -> [Double] {
    var weights = Array(repeating: 0.0, count: pose.vertices.count)
    let plan = suppliedPlan ?? GripPlan(pose: pose)
    let surface = GripZoneSurface(pose: pose, gripPlan: plan, hand: hand)
    func smooth(_ value: Double) -> Double {
      let t = min(1, max(0, value))
      return t * t * (3 - 2 * t)
    }
    for zone in plan.zones {
      guard let highlight = zone.highlight else { continue }
      let amount = pressureAmount(highlight.intensity)
      guard amount > 0 else { continue }
      switch highlight.region {
      case .wrist:
        // A circumferential mask: back, palm, thumb side, and pinky side all
        // show the same stabilization instruction, fading only into the hand.
        for i in pose.vertices.indices {
          weights[i] = max(weights[i], amount * (1 - smooth(hand.vertices[i][1] / 18)))
        }
      case .palm:
        let zi = GripZoneSurface.zones.firstIndex(of: .palm)!
        for i in pose.vertices.indices {
          weights[i] = max(weights[i], amount * surface.weights[i][zi])
        }
      case .fingerPad, .fingerSide, .curledFinger:
        guard let f = zone.zoneId.finger else { continue }
        let wrapped = highlight.region != .fingerPad || wrapsMiddle(f, pitch: pose.pitch)
        let start = highlight.region == .curledFinger ? 0 : wrapped ? 1 : 2
        let bones = f.jointNames[start...].compactMap { name in
          hand.joints.firstIndex { $0.name == name }
        }
        let candidates =
          highlight.region == .fingerPad
          ? contactIndices(hand: hand, finger: f, pitch: pose.pitch)
          : hand.vertices.indices.filter { i in bones.reduce(0.0) { $0 + hand.weights[i][$1] } > 0.6
          }
        // Anchor shading near the intended interaction, but never discard an
        // instructed region because a contact or placement category differs.
        let nearest = candidates.sorted {
          abs(simd_distance(pose.vertices[$0], pose.ballCenter) - ballRadius)
            < abs(simd_distance(pose.vertices[$1], pose.ballCenter) - ballRadius)
        }.prefix(80)
        let samples = nearest.map { pose.vertices[$0] }
        guard !samples.isEmpty else { continue }
        for i in pose.vertices.indices {
          let influence = bones.reduce(0.0) { $0 + hand.weights[i][$1] }
          guard influence > 0.25 else { continue }
          let distance = samples.map { simd_distance(pose.vertices[i], $0) }.min()!
          weights[i] = max(
            weights[i],
            amount * exp(-pow(distance / (wrapped ? 30 : 22), 2))
              * smooth((influence - 0.25) / 0.5))
        }
      }
    }
    // Diffuse on connected skin, so the colored region has a soft boundary and
    // remains readable from the side of an otherwise hidden contact patch.
    var neighbors = Array(repeating: Set<Int>(), count: weights.count)
    for t in stride(from: 0, to: hand.indices.count, by: 3) {
      let a = Int(hand.indices[t])
      let b = Int(hand.indices[t + 1])
      let c = Int(hand.indices[t + 2])
      neighbors[a].formUnion([b, c])
      neighbors[b].formUnion([a, c])
      neighbors[c].formUnion([a, b])
    }
    for _ in 0..<8 {
      weights = weights.indices.map { i in
        let nearby = neighbors[i]
        return weights[i] * 0.5 + nearby.reduce(0) { $0 + weights[$1] }
          / Double(max(1, nearby.count)) * 0.5
      }
    }
    return weights
  }
  /// SceneKit vertex colors are linear RGB; the legend's palette is sRGB.
  /// Interpolate perceptually, then decode so pine does not render as pale mint.
  public static func pressureColor(_ weight: Double) -> SIMD3<Float> {
    let t = min(1, max(0, weight))
    func linear(_ channel: Double) -> Float {
      Float(channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4))
    }
    return SIMD3(linear(1 - 0.965 * t), linear(1 - 0.71 * t), linear(1 - 0.79 * t))
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
        !(pitch == .circleChange && f == .index)
      else { continue }
      let amount = pressureAmount(pressure)
      guard amount > 0 else { continue }
      var regions = [padIndices(hand: hand, finger: f)]
      if wrapsMiddle(f, pitch: pitch) {
        regions.append(middleContactIndices(hand: hand, finger: f))
      }
      for ids in regions {
        let closest = ids.sorted {
          abs(simd_distance(vertices[$0], center) - ballRadius)
            < abs(simd_distance(vertices[$1], center) - ballRadius)
        }.prefix(12)
        guard !closest.isEmpty else { continue }
        let contact =
          closest.reduce(SIMD3<Double>.zero) { $0 + vertices[$1] } / Double(closest.count)
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
    }
    return result
  }
}
