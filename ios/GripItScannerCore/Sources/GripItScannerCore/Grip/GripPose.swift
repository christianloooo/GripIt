import Foundation
import simd

public struct GripFingerPose: Sendable {
  public let finger: GripFinger
  public var points: [SIMD3<Double>]
  public let lengths: [Double]
  public let radius: Double
  public var angles: [Double]
  public var allowsOpposition: Bool = false
  public var opposition: Double = 0
  public var yaw: Double
  public var target: SIMD3<Double>
  public var targetError: Double = 0
  public var clearance: Double = 0
  public let contact: Bool
  public var preferredCurl: [Double]? = nil
  public var minimumKnuckleCurl: Double = -0.15
  public var spreadLimit: Double = 0.4
}
public struct GripPose: Sendable {
  public let id = UUID()
  public let pitch: PitchGrip
  public let handedness: Handedness
  public let ballCenter: SIMD3<Double>
  public let ballRotation: simd_quatd
  public let fingers: [GripFingerPose]
  public let vertices: [SIMD3<Double>]
  public let indices: [UInt32]
  public let diagnostics: GripFitDiagnostics
}
public struct GripSeamFit: Sendable {
  public let finger: GripFinger
  public let distanceMm: Double
  public let tangentAlignment: Double
  public let across: Bool
  public let leather: Bool
  public var needsReview: Bool {
    leather
      ? distanceMm < 3
      : distanceMm > 3 || (across ? tangentAlignment > 0.5 : tangentAlignment < 0.75)
  }
}
public struct GripFitDiagnostics: Sendable {
  public let maximumContactGapMm: Double
  public let maximumSkinPenetrationMm: Double
  public let maximumPadSurfaceGapMm: Double
  public let maximumEdgeStretch: Double
  public let loopGapMm: Double?
  public let modeledThickness: Bool
  public let usedMeasuredRoots: Bool
  public let seams: [GripSeamFit]
  public var adjustedProportions = false
  public var needsReview: Bool {
    maximumContactGapMm > 6 || maximumSkinPenetrationMm > 3 || maximumPadSurfaceGapMm > 3
      || (loopGapMm ?? 0) > 5
      || seams.contains(where: \.needsReview)
  }
}

public enum GripPoseSolver {
  public static let ballRadius = 36.5
  public static func solve(profile: HandProfile, pitch: PitchGrip) throws -> GripPose {
    try solve(
      profile: profile, pitch: pitch, hand: GripHandAsset.load(), ball: GripBallAsset.load())
  }
  public static func solve(
    profile: HandProfile, pitch: PitchGrip, hand: GripHandAsset, ball: GripBallAsset
  ) throws -> GripPose {
    try Task.checkCancellation()
    let fit = try initialFit(profile: profile, pitch: pitch, hand: hand)
    var fingers = fit.fingers
    let scale = fit.scale
    let length = fit.length
    let measuredRoots = fit.measuredRoots
    var center = SIMD3(0, length + 8, pitch == .circleChange ? 46.0 : 48.0)
    func upperNormal(_ finger: GripFinger) -> SIMD3<Double> {
      switch finger {
      case .index: unit(SIMD3(pitch == .slider ? 0.20 : 0.31, 0.65, 0.70))
      case .middle: unit(SIMD3(pitch == .circleChange ? 0.24 : -0.16, 0.65, 0.70))
      default: unit(SIMD3(-0.40, 0.65, 0.70))
      }
    }
    func targets(_ center: SIMD3<Double>) -> [SIMD3<Double>] {
      fingers.map { rig in
        let f = rig.finger
        let r = ballRadius + rig.radius * (pitch.upperContacts.contains(f) ? 0.6 : 0.8)
        if pitch == .circleChange && f == .index {
          return center + SIMD3(24, -27, 13)
        }
        let direction: SIMD3<Double>
        switch f {
        case .index: direction = upperNormal(f)
        case .middle: direction = upperNormal(f)
        case .ring:
          if pitch != .circleChange {
            var tucked = rig
            tucked.angles = rig.preferredCurl ?? [0.9, 1.6, 1.1]
            tucked.yaw = 0.18
            tucked.opposition = -0.08
            return forward(tucked).last!
          }
          direction = pitch == .circleChange ? SIMD3(-0.40, 0.65, 0.70) : SIMD3(-0.72, 0.58, 0.38)
        case .pinky:
          if pitch != .circleChange {
            var relaxed = rig
            relaxed.angles = rig.preferredCurl ?? [1.1, 1.5, 1.0]
            relaxed.yaw = 0.22
            relaxed.opposition = -0.08
            return forward(relaxed).last!
          }
          direction = SIMD3(-0.90, -0.28, 0.32)
        case .thumb:
          // Seed the thumb beneath the principal contacts. Actual skin support
          // is then fitted in the lower, central quadrant of the ball.
          let opposing = pitch.upperContacts.map(upperNormal)
          let midpoint = opposing.reduce(SIMD3<Double>.zero, +) / Double(max(1, opposing.count))
          direction = SIMD3(0.10 - midpoint.x * 0.15, -0.92, 0.38)
        }
        return center + unit(direction) * r
      }
    }
    func assign() {
      let ts = targets(center)
      for i in fingers.indices { fingers[i].target = ts[i] }
    }
    assign()
    for i in fingers.indices {
      try Task.checkCancellation()
      optimize(&fingers[i], center: center, others: [], multistart: true)
    }
    // Couple fingers and ball placement. Avoid forcing every hand into one
    // adult-size pose; dimensions and all FK segment lengths remain measured.
    for _ in 0..<5 {
      try Task.checkCancellation()
      for i in fingers.indices {
        let others = fingers.enumerated().filter { $0.offset != i }.map(\.element)
        optimize(&fingers[i], center: center, others: others, multistart: false)
      }
      var best = center
      var score = cost(fingers, center: center)
      for axis in 0..<3 {
        for sign in [-1.0, 1.0] {
          var candidate = center
          candidate[axis] += sign * 2
          guard abs(candidate.x) < 10, abs(candidate.y - (length + 8)) < 12,
            44.0...56.0 ~= candidate.z
          else { continue }
          let ts = targets(candidate)
          var trial = fingers
          for i in trial.indices {
            trial[i].target = ts[i]
            update(&trial[i], center: candidate)
          }
          let value = cost(trial, center: candidate)
          if value < score {
            best = candidate
            score = value
          }
        }
      }
      center = best
      assign()
    }
    for i in fingers.indices {
      let others = fingers.enumerated().filter { $0.offset != i }.map(\.element)
      optimize(&fingers[i], center: center, others: others, multistart: true)
    }
    if pitch != .circleChange {
      for i in fingers.indices where fingers[i].finger == .ring || fingers[i].finger == .pinky {
        fingers[i].angles = fingers[i].preferredCurl!
        fingers[i].yaw = fingers[i].finger == .ring ? 0.32 : 0.22
        fingers[i].opposition = -0.08
        update(&fingers[i], center: center)
      }
    }
    for i in fingers.indices where pitch.upperContacts.contains(fingers[i].finger) {
      fingers[i].angles = [0.8, 0.8, 0.6]
      fingers[i].yaw = fingers[i].finger == .ring ? 0.08 : 0
      fingers[i].opposition = 0
      update(&fingers[i], center: center)
    }
    if hand.preserveAuthoredAnatomy == true {
      let refined = try fitAuthoredSurface(
        hand: hand, fingers: fingers, scale: scale, center: center, pitch: pitch)
      fingers = refined.fingers
      center = refined.center
    }
    let uncompressed = try deform(hand: hand, fingers: fingers, scale: scale, center: center)
    let vertices = compressContacts(
      hand: hand, vertices: uncompressed, fingers: fingers,
      center: center, pitch: pitch)
    let rotation = orientBall(
      ball, pitch: pitch, fingers: fingers, center: center, hand: hand, vertices: vertices)
    var stretch = 1.0
    var penetration = 0.0
    for v in vertices { penetration = max(penetration, ballRadius - simd_distance(v, center)) }
    // Distortion is measured against each personalized bone's size, not only
    // a finite bounding box. Profile error cannot quietly make a torn mesh.
    for i in stride(from: 0, to: hand.indices.count, by: 3) {
      for j in 0..<3 {
        let a = Int(hand.indices[i + j])
        let b = Int(hand.indices[i + (j + 1) % 3])
        let old = simd_distance(gv(hand.vertices[a]) * scale, gv(hand.vertices[b]) * scale)
        if old > 0.7 { stretch = max(stretch, simd_distance(vertices[a], vertices[b]) / old) }
      }
    }
    guard penetration < 6 else {
      throw GripError.invalid(
        "This grip would overlap the ball too much for these proportions. Try another pitch; rescan only if the measurements look wrong."
      )
    }
    guard stretch < 7, vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
    else {
      throw GripError.invalid(
        "This profile creates an overstretched hand surface. Please rescan rather than using a distorted grip."
      )
    }
    let contacts = fingers.filter {
      $0.contact && !(pitch == .circleChange && $0.finger == .index)
    }
    let padSurfaceGap =
      contacts.map { finger in
        padVertices(hand: hand, vertices: vertices, finger: finger.finger).map {
          abs(simd_distance($0, center) - ballRadius)
        }.min() ?? Double.infinity
      }.max() ?? 0
    // This photo-guided changeup wraps the index beside the ball. A closed
    // index–thumb circle is optional; it must never displace the supporting thumb.
    let loop: Double? = nil
    return GripPose(
      pitch: pitch, handedness: profile.handedness, ballCenter: center, ballRotation: rotation,
      fingers: fingers, vertices: vertices, indices: hand.indices,
      diagnostics: GripFitDiagnostics(
        maximumContactGapMm: contacts.map { finger in
          let gaps = padVertices(hand: hand, vertices: vertices, finger: finger.finger)
            .map { abs(simd_distance($0, center) - ballRadius) }.sorted().prefix(12)
          return sqrt(gaps.reduce(0) { $0 + $1 * $1 } / Double(max(1, gaps.count)))
        }.max() ?? 0,
        maximumSkinPenetrationMm: max(0, penetration), maximumPadSurfaceGapMm: padSurfaceGap,
        maximumEdgeStretch: stretch, loopGapMm: loop,
        modeledThickness: profile.measurements.palm.thicknessMm == nil
          || GripFinger.allCases.contains {
            $0.measurement(profile).diameterMm == nil
          }, usedMeasuredRoots: measuredRoots,
        seams: inspectSeams(
          ball, pitch: pitch, fingers: fingers, center: center, rotation: rotation, hand: hand,
          vertices: vertices),
        adjustedProportions: fit.limited))
  }
  /// Neutral anatomy review uses the same personalized bind surface as the grip renderer.
  /// No baseball or inverse-kinematics target can hide a malformed base hand here.
  public static func openHand(profile: HandProfile, flexion: Double = 0) throws -> GripPose {
    guard flexion.isFinite, (0...0.65).contains(flexion) else {
      throw GripError.invalid("Review flexion must be between 0 and 0.65.")
    }
    let hand = try GripHandAsset.load()
    let fit = try initialFit(profile: profile, pitch: .fourSeam, hand: hand)
    var fingers = fit.fingers
    for i in fingers.indices {
      let names = fingers[i].finger.jointNames
      let rest = names.map { name in gv(hand.joints.first { $0.name == name }!.position) }
      let sourceDirection = unit(rest[1] - rest[0])
      let splay: Double
      switch fingers[i].finger {
      case .thumb: splay = atan2(sourceDirection.x, sourceDirection.y)
      case .index: splay = -1 * .pi / 180
      case .middle: splay = 0
      case .ring: splay = 1 * .pi / 180
      case .pinky: splay = 3 * .pi / 180
      }
      let relax = simd_quatd(
        angle: atan2(sourceDirection.x, sourceDirection.y) - splay, axis: SIMD3(0, 0, 1))
      let axis = unit(simd_cross(relax.act(sourceDirection), SIMD3(0, 0, 1)))
      var bend = 0.0
      for j in 0..<3 {
        bend += flexion * [0.7, 1.05, 0.52][j]
        let rotation = simd_quatd(angle: bend, axis: axis)
        fingers[i].points.append(
          fingers[i].points[j] + rotation.act(relax.act(unit(rest[j + 1] - rest[j])))
            * fingers[i].lengths[j])
      }
    }
    let vertices = try deform(hand: hand, fingers: fingers, scale: fit.scale, center: .zero)
    return GripPose(
      pitch: .fourSeam, handedness: profile.handedness, ballCenter: SIMD3(0, 60, 300),
      ballRotation: simd_quatd(), fingers: fingers, vertices: vertices, indices: hand.indices,
      diagnostics: GripFitDiagnostics(
        maximumContactGapMm: 0, maximumSkinPenetrationMm: 0,
        maximumPadSurfaceGapMm: 0, maximumEdgeStretch: 1, loopGapMm: nil,
        modeledThickness: true, usedMeasuredRoots: fit.measuredRoots, seams: [],
        adjustedProportions: fit.limited))
  }
  static func initialFit(profile: HandProfile, pitch: PitchGrip, hand: GripHandAsset) throws
    -> (
      fingers: [GripFingerPose], scale: SIMD3<Double>, width: Double, length: Double,
      measuredRoots: Bool, limited: Bool
    )
  {
    guard profile.coordinateSystem == "gripit-hand-v1" else {
      throw GripError.invalid("Unsupported hand coordinate system.")
    }
    guard let width = profile.measurements.palm.widthMm,
      let length = profile.measurements.palm.lengthMm,
      width.isFinite, length.isFinite, (40...125).contains(width), (35...125).contains(length)
    else {
      throw GripError.invalid(
        "This profile needs valid measured palm width and length before a grip can be built.")
    }
    let rest = Dictionary(uniqueKeysWithValues: hand.joints.map { ($0.name, gv($0.position)) })
    let restWidth = simd_distance(
      rest["index-finger-phalanx-proximal"]!, rest["pinky-finger-phalanx-proximal"]!)
    let restLength = simd_length(
      (rest["index-finger-phalanx-proximal"]! + rest["pinky-finger-phalanx-proximal"]!) / 2)
    let preserve = hand.preserveAuthoredAnatomy == true
    let uniform = width / restWidth
    var limited = false
    func bounded(_ requested: Double, reference: Double, lo: Double, hi: Double) -> Double {
      let result = min(reference * hi, max(reference * lo, requested))
      if abs(result - requested) > 0.001 { limited = true }
      return result
    }
    // Unknown depth is not a thin-palm measurement. Preserve the source anatomy.
    let scale =
      preserve
      ? SIMD3(
        uniform,
        bounded(length / restLength, reference: uniform, lo: 0.9, hi: 1.1),
        profile.measurements.palm.thicknessMm.map {
          bounded($0 / hand.palmReferenceThickness, reference: uniform, lo: 0.85, hi: 1.15)
        } ?? uniform
      )
      : SIMD3(
        uniform, length / restLength,
        (profile.measurements.palm.thicknessMm ?? 14) / hand.palmReferenceThickness)
    func palm(_ p: SIMD3<Double>) -> SIMD3<Double> { p * scale }
    var measuredRoots = false
    var fingers: [GripFingerPose] = []
    for f in GripFinger.allCases {
      let m = f.measurement(profile)
      var lengths = m.segmentsMm
      guard lengths.count == 3, lengths.allSatisfy({ $0.isFinite && (6...65).contains($0) }),
        lengths.max()! / lengths.min()! < 4
      else {
        throw GripError.invalid(
          "\(f.title) segment measurements are invalid. Scan the whole finger again.")
      }
      if preserve {
        let references = f.jointNames.map { rest[$0]! }
        lengths = lengths.enumerated().map { i, measured in
          bounded(
            measured, reference: simd_distance(references[i], references[i + 1]) * uniform,
            lo: 0.8, hi: 1.2)
        }
      }
      let authoredDiameter = hand.authoredFingerRadii?[f.rawValue].map { $0 * 2 * uniform }
      let requestedDiameter =
        m.diameterMm ?? authoredDiameter
        ?? (f == .thumb ? 16 : f == .pinky ? 11 : 13.5) * width / 62
      let diameter =
        preserve && authoredDiameter != nil
        ? bounded(requestedDiameter, reference: authoredDiameter!, lo: 0.85, hi: 1.15)
        : requestedDiameter
      guard diameter.isFinite, (5...30).contains(diameter) else {
        throw GripError.invalid("Invalid \(f.title) thickness.")
      }
      var root = palm(rest[f.jointNames[0]]!)
      if let m = profile.landmarks[f.landmarkRoot], m.confidence >= 0.5,
        [m.xMm, m.yMm, m.zMm].allSatisfy(\.isFinite), abs(m.xMm) < width,
        (0...length * 1.4).contains(m.yMm)
      {
        guard abs(m.zMm) < 30 else {
          throw GripError.invalid(
            "\(f.title) base depth is inconsistent with the palm. Rescan with the whole hand visible."
          )
        }
        let measured = SIMD3(m.xMm, m.yMm, m.zMm)
        if preserve {
          // Keep the authored MCP arch/thenar pad. Sparse surface landmarks
          // must not independently drag the finger bases through the palm.
          let delta = measured - root
          let offset = SIMD3(
            min(3, max(-3, delta.x * 0.35)), min(3, max(-3, delta.y * 0.35)),
            min(3, max(-3, delta.z * 0.35)))
          root += offset
          if simd_distance(root, measured) > 0.1 { limited = true }
        } else {
          root = measured
        }
        measuredRoots = true
      }
      fingers.append(
        GripFingerPose(
          finger: f, points: [root], lengths: lengths, radius: diameter / 2,
          angles: f == .thumb ? [0.65, 0.9, 0.6] : [0.35, 1.1, 0.9],
          allowsOpposition: f == .thumb,
          opposition: f == .thumb ? 0.4 : 0,
          yaw: f == .thumb ? 0.2 : 0, target: .zero,
          contact: pitch.upperContacts.contains(f) || f == .thumb
            || (pitch == .circleChange && f == .pinky),
          preferredCurl: pitch != .circleChange && f == .ring
            ? [0.9, 1.6, 1.1]
            : pitch != .circleChange && f == .pinky
              ? [1.1, 1.5, 1.0]
              : pitch == .circleChange && f == .index ? [1.2, 1.6, 1.05] : nil,
          minimumKnuckleCurl: pitch == .circleChange && f == .index
            ? 1.0 : pitch.upperContacts.contains(f) ? 0.65 : -0.15,
          spreadLimit: f == .middle || (f == .index && pitch != .circleChange) ? 0.18 : 0.4))
    }
    return (fingers, scale, width, length, measuredRoots, limited)
  }
  static func forward(_ rig: GripFingerPose) -> [SIMD3<Double>] {
    var points = [rig.points[0]]
    var bend = 0.0
    let u =
      rig.finger == .thumb
      ? SIMD3(cos(rig.yaw), sin(rig.yaw), 0) : SIMD3(-sin(rig.yaw), cos(rig.yaw), 0)
    let candidate =
      rig.finger == .thumb
      ? SIMD3(0, sin(rig.opposition), cos(rig.opposition))
      : SIMD3(sin(rig.opposition), 0, cos(rig.opposition))
    let v = unit(candidate - u * simd_dot(candidate, u))
    for j in 0..<3 {
      bend += rig.angles[j]
      points.append(points.last! + (u * cos(bend) + v * sin(bend)) * rig.lengths[j])
    }
    return points
  }
  static func update(_ rig: inout GripFingerPose, center: SIMD3<Double>) {
    constrain(&rig)
    rig.points = forward(rig)
    rig.targetError = simd_distance(rig.points[3], rig.target)
    rig.clearance = (0..<3).map {
      segmentDistance(center, rig.points[$0], capsuleEnd(rig, $0)) - ballRadius - rig.radius
    }.min()!
  }
  /// The long fingers curl in a nearly fixed plane; they cannot oppose like
  /// thumbs. Couple distal flexion to the middle joint instead of allowing a
  /// straight middle phalanx with an independently folded-back fingertip.
  static func constrain(_ rig: inout GripFingerPose) {
    if rig.finger == .thumb {
      rig.angles = zip(rig.angles, [1.1, 1.35, 1.25]).map { min($1, max(0.1, $0)) }
      rig.yaw = min(2.2, max(0.1, rig.yaw))
      rig.opposition = min(1.35, max(0, rig.opposition))
    } else {
      rig.angles[0] = min(1.45, max(rig.minimumKnuckleCurl, rig.angles[0]))
      rig.angles[1] = min(1.65, max(0, rig.angles[1]))
      if rig.preferredCurl != nil && [.ring, .pinky].contains(rig.finger) {
        // Photo-reference pose: fold support fingertips back toward the palm,
        // rather than satisfying clearance with extended fingers beside the ball.
        rig.angles[0] = max(rig.finger == .ring ? 0.8 : 0.9, rig.angles[0])
        rig.angles[1] = max(rig.finger == .ring ? 1.4 : 1.3, rig.angles[1])
        rig.angles[2] = max(0.85, rig.angles[2])
      }
      rig.angles[2] = min(
        1.15,
        min(
          rig.angles[1] * 0.85 + 0.12,
          max(rig.angles[1] * 0.35, rig.angles[2])))
      rig.yaw = min(rig.spreadLimit, max(-rig.spreadLimit, rig.yaw))
      rig.opposition = min(0.12, max(-0.12, rig.opposition))
      if rig.minimumKnuckleCurl > 0 {
        rig.opposition = 0
        if rig.finger == .index { rig.yaw = max(0, rig.yaw) }
        if rig.finger == .middle { rig.yaw = min(0, rig.yaw) }
      }
    }
  }
  static func capsuleEnd(_ rig: GripFingerPose, _ segment: Int) -> SIMD3<Double> {
    // The last measured point is the skin tip, not a capsule center. Inset the
    // distal collider so its rounded cap ends at that measured point.
    segment == 2
      ? rig.points[3] - unit(rig.points[3] - rig.points[2]) * min(rig.radius, rig.lengths[2] * 0.45)
      : rig.points[segment + 1]
  }
  static func segmentDistance(_ p: SIMD3<Double>, _ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double
  {
    let d = b - a
    let t = max(0, min(1, simd_dot(p - a, d) / max(1e-9, simd_length_squared(d))))
    return simd_distance(p, a + d * t)
  }
  static func energy(_ r: GripFingerPose, center: SIMD3<Double>, others: [GripFingerPose]) -> Double
  {
    var value = r.targetError * r.targetError
    for j in 0..<3 {
      value +=
        180
        * pow(
          max(0, ballRadius + r.radius - segmentDistance(center, r.points[j], capsuleEnd(r, j))), 2)
      // Exposed joints should not pass through adjacent fingers. Webbing
      // at the bases is intentionally shared by the connected palm mesh.
      for other in others {
        for k in 1..<4 {
          let otherPoint = k == 3 ? capsuleEnd(other, 2) : other.points[k]
          let gap = segmentDistance(otherPoint, r.points[j], capsuleEnd(r, j))
          value +=
            25
            * pow(
              max(0, r.radius * (j == 2 ? 0.8 : 1) + other.radius * (k == 3 ? 0.8 : 1) - gap), 2)
        }
      }
    }
    value += r.angles.enumerated().reduce(0) {
      $0 + (r.preferredCurl == nil ? 0.5 : 60)
        * pow($1.element - (r.preferredCurl ?? [0.3, 1.0, 0.7])[$1.offset], 2)
    }
    return value
  }
  static func cost(_ rigs: [GripFingerPose], center: SIMD3<Double>) -> Double {
    rigs.reduce(0) { $0 + energy($1, center: center, others: []) }
  }
  static func optimize(
    _ r: inout GripFingerPose, center: SIMD3<Double>, others: [GripFingerPose], multistart: Bool
  ) {
    var best = r
    var bestCost = Double.infinity
    let seeds =
      multistart
      ? [
        [0.2, 0.9, 0.8], [0.6, 1.2, 1.0], [1.1, 0.5, 0.3], [1.45, 1.4, 0.2], [-0.2, 1.5, 1.2],
        r.angles,
      ] : [r.angles]
    for (seedIndex, seed) in seeds.enumerated() {
      r.angles = seed.enumerated().map { j, a in
        max(
          r.finger == .thumb && j == 0 ? 0.1 : (j == 0 ? -0.35 : 0),
          min(r.finger == .thumb ? [1.1, 1.5, 1.4][j] : [1.5, 1.85, 1.7][j], a))
      }
      if multistart {
        r.yaw = r.finger == .thumb ? [0.4, 1.1, 1.8, 2.1, 0.8, 1.5][seedIndex] : 0
        if r.finger == .thumb { r.opposition = [0.4, 0.8, 1.0, 0.6, 1.2, 0.3][seedIndex] }
      }
      for step in [0.25, 0.09, 0.03, 0.01] {
        for _ in 0..<12 {
          var changed = false
          for j in 0..<5 {
            update(&r, center: center)
            var chosen = r
            var score = energy(r, center: center, others: others)
            for sign in [-1.0, 1.0] {
              var trial = r
              if j == 4 {
                trial.opposition += sign * step
              } else if j == 3 {
                trial.yaw += sign * step
              } else {
                trial.angles[j] += sign * step
              }
              // Clamp a complete candidate copy. Coupled joint limits must not
              // mutate the accepted pose while evaluating a rejected trial.
              update(&trial, center: center)
              let next = energy(trial, center: center, others: others)
              if next < score {
                score = next
                chosen = trial
                changed = true
              }
            }
            r = chosen
          }
          if !changed { break }
        }
      }
      update(&r, center: center)
      let score = energy(r, center: center, others: others)
      if score < bestCost {
        best = r
        bestCost = score
      }
    }
    r = best
    update(&r, center: center)
  }
}
