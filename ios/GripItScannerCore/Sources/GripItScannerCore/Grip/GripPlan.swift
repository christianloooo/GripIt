import Foundation
import simd

/// Stable interchange IDs. A zone's ID does not change when its contact role changes.
public enum GripZoneID: String, CaseIterable, Codable, Sendable, Identifiable {
  case indexPad = "index-pad"
  case middlePad = "middle-pad"
  case ringSide = "ring-side"
  case pinky
  case thumbPad = "thumb-pad"
  case palm, wrist
  public var id: String { rawValue }
  public var finger: GripFinger? {
    switch self {
    case .indexPad: .index
    case .middlePad: .middle
    case .ringSide: .ring
    case .pinky: .pinky
    case .thumbPad: .thumb
    default: nil
    }
  }
  public var title: String {
    switch self {
    case .indexPad: "Index finger"
    case .middlePad: "Middle finger"
    case .ringSide: "Ring finger"
    case .pinky: "Pinky"
    case .thumbPad: "Thumb"
    case .palm: "Palm"
    case .wrist: "Wrist"
    }
  }
}
public enum GripPressure: String, Codable, Sendable { case none, light, medium, firm }
public enum GripRole: String, Codable, Sendable { case drive, support, clear }
public enum GripReach: String, Codable, Sendable {
  case comfortable, strained, unreachable
  /// Engineering tolerances on geometric contact error, not clinical limits.
  public static func classify(shortfallMm: Double) -> Self {
    guard shortfallMm.isFinite else { return .unreachable }
    return shortfallMm <= 3 ? .comfortable : shortfallMm <= 8 ? .strained : .unreachable
  }
}
public struct GripPlacement: Codable, Sendable {
  public enum Surface: String, Codable, Sendable { case pad, tip, side, curl, none }
  public enum Region: String, Codable, Sendable {
    case top, underside
    case thumbSide = "thumb-side"
    case pinkySide = "pinky-side"
    case offBall = "off-ball"
  }
  public enum Seam: String, Codable, Sendable { case across, along, beside, off, none }
  public let surface: Surface
  public let region: Region
  public let seam: Seam
  public let seamOffsetMm: Double?
  public let opposes: [GripZoneID]
}
public struct GripZonePlan: Codable, Sendable, Identifiable {
  public let zoneId: GripZoneID
  public var title: String { zoneId.title }
  public var id: GripZoneID { zoneId }
  public let instruction: String
  public let pressure: GripPressure?
  public let role: GripRole?
  public var reach: GripReach = .comfortable
  public var shortfallMm: Double? = nil
  public var reachEvidence: String = "Not fitted"
  public let placement: GripPlacement?
  public var extrapolated: Bool = false

  // Encode title as part of the public interchange contract, although it is derived locally.
  private enum CodingKeys: String, CodingKey {
    case zoneId, title, instruction, pressure, role, reach, shortfallMm, reachEvidence, placement,
      extrapolated
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    zoneId = try c.decode(GripZoneID.self, forKey: .zoneId)
    instruction = try c.decode(String.self, forKey: .instruction)
    pressure = try c.decodeIfPresent(GripPressure.self, forKey: .pressure)
    role = try c.decodeIfPresent(GripRole.self, forKey: .role)
    reach = try c.decode(GripReach.self, forKey: .reach)
    shortfallMm = try c.decodeIfPresent(Double.self, forKey: .shortfallMm)
    reachEvidence = try c.decodeIfPresent(String.self, forKey: .reachEvidence) ?? "Not supplied"
    placement = try c.decodeIfPresent(GripPlacement.self, forKey: .placement)
    extrapolated = try c.decodeIfPresent(Bool.self, forKey: .extrapolated) ?? false
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(zoneId, forKey: .zoneId)
    try c.encode(title, forKey: .title)
    try c.encode(instruction, forKey: .instruction)
    try c.encode(pressure, forKey: .pressure)
    try c.encode(role, forKey: .role)
    try c.encode(reach, forKey: .reach)
    try c.encode(shortfallMm, forKey: .shortfallMm)
    try c.encode(reachEvidence, forKey: .reachEvidence)
    try c.encode(placement, forKey: .placement)
    try c.encode(extrapolated, forKey: .extrapolated)
  }
  init(
    _ zone: GripZoneID, _ text: String, _ pressure: GripPressure?, _ role: GripRole?,
    _ placement: GripPlacement?
  ) {
    zoneId = zone
    instruction = text
    self.pressure = pressure
    self.role = role
    self.placement = placement
    extrapolated = zone == .wrist
  }
}
public struct GripPlan: Codable, Sendable {
  public let pitch: PitchGrip
  public let zones: [GripZonePlan]
  public init(pose: GripPose) {
    pitch = pose.pitch
    let hand = try? GripHandAsset.load()
    let pitch = pose.pitch
    zones = pitch.zoneTemplates.map { template in
      var zone = template
      if let finger = pose.fingers.first(where: { $0.finger == zone.zoneId.finger }), let hand {
        let surfaces: [SIMD3<Double>]
        if zone.placement?.surface == .side || zone.zoneId == .pinky {
          let jointIndices = finger.finger.jointNames.compactMap { name in
            hand.joints.firstIndex { $0.name == name }
          }
          surfaces = pose.vertices.indices.filter { i in
            jointIndices.reduce(0) { $0 + hand.weights[i][$1] } > 0.7
          }.map { pose.vertices[$0] }
        } else {
          surfaces = GripPoseSolver.padVertices(
            hand: hand, vertices: pose.vertices, finger: finger.finger)
        }
        let minimumGap =
          surfaces.map { simd_distance($0, pose.ballCenter) - GripPoseSolver.ballRadius }.min()
          ?? .infinity
        let penetration = max(0, -minimumGap)
        var error = zone.role == .clear ? penetration : max(penetration, max(0, minimumGap))
        if pitch == .circleChange && [.indexPad, .thumbPad].contains(zone.zoneId) {
          error = pose.diagnostics.loopGapMm ?? .infinity
        }
        zone.shortfallMm = max(0, error)
        zone.reach = .classify(shortfallMm: error)
        zone.reachEvidence =
          "Actual skin gap / overlap; circle-change loop uses index–thumb pad distance. 3 mm comfortable, 8 mm strained."
      } else if zone.zoneId == .palm, let hand {
        let points = pose.vertices.indices.filter { i in
          let v = hand.vertices[i]
          return v[1] > 18 && v[1] < 62 && abs(v[0]) < 23 && v[2] > 5
        }.map { pose.vertices[$0] }
        let gap =
          points.map { simd_distance($0, pose.ballCenter) - GripPoseSolver.ballRadius }.min()
          ?? .infinity
        let error = zone.role == .clear ? max(0, 2 - gap) : abs(gap)
        zone.shortfallMm = error
        zone.reach = .classify(shortfallMm: error)
        zone.reachEvidence =
          zone.role == .clear
          ? "Clearance against a 2 mm modeled palm gap." : "Modeled palm surface distance to ball."
      } else {
        zone.reachEvidence =
          "No wrist reach constraint is defined; comfortable means no geometric target. Wrist guidance is extrapolated and is not measured."
      }
      return zone
    }
  }
}

extension PitchGrip {
  public var zoneTemplates: [GripZonePlan] {
    func place(
      _ surface: GripPlacement.Surface, _ region: GripPlacement.Region, _ seam: GripPlacement.Seam,
      _ opposes: [GripZoneID] = []
    ) -> GripPlacement {
      GripPlacement(
        surface: surface, region: region, seam: seam,
        seamOffsetMm: seam == .across || seam == .along ? 0 : nil, opposes: opposes)
    }
    let change = self == .circleChange
    let slider = self == .slider
    let seam: GripPlacement.Seam = self == .fourSeam ? .across : .along
    var zones = [
      GripZonePlan(
        .indexPad, instructionText(.indexPad), change || slider ? .light : .medium,
        change || slider ? .support : .drive,
        change
          ? place(.curl, .thumbSide, .off, [.thumbPad]) : place(.pad, .top, slider ? .beside : seam)
      ),
      GripZonePlan(
        .middlePad, instructionText(.middlePad), self == .fourSeam || slider ? .firm : .medium,
        .drive, place(.pad, .top, seam)),
      GripZonePlan(
        .ringSide, instructionText(.ringSide), change ? .medium : .light,
        change ? .drive : .support,
        change ? place(.pad, .top, .along) : place(.side, .pinkySide, .off)),
      GripZonePlan(
        .pinky, instructionText(.pinky), change ? .light : GripPressure.none,
        change ? .support : .clear,
        change ? place(.curl, .pinkySide, .off) : place(.none, .offBall, .none)),
      GripZonePlan(
        .thumbPad, instructionText(.thumbPad), .light, .support,
        place(
          .pad, change ? .thumbSide : .underside, .off,
          change ? [.indexPad] : slider ? [.middlePad] : [.indexPad, .middlePad])),
    ]
    if !slider {
      zones.append(
        GripZonePlan(
          .palm, instructionText(.palm), change ? .light : GripPressure.none,
          change ? .support : .clear, nil))
    }
    zones.append(
      GripZonePlan(
        .wrist, instructionText(.wrist), change ? nil : .firm, change ? nil : .drive, nil))
    return zones
  }
  private func instructionText(_ zone: GripZoneID) -> String {
    switch (self, zone) {
    case (.fourSeam, .indexPad): "Pad across the raised stitching, seam crossing underneath."
    case (.fourSeam, .middlePad): "Beside the index, pad also crossing the stitching."
    case (.twoSeam, .indexPad): "Pad along the thumb-side seam, following its direction."
    case (.twoSeam, .middlePad): "Pad along the other seam, toward the pinky side."
    case (.slider, .indexPad): "Rests on smooth leather beside the middle finger, stabilising."
    case (.slider, .middlePad): "Pad along the pinky-side seam with definite purchase."
    case (.circleChange, .indexPad):
      "Curled around the thumb-side surface, forming a loop with the thumb."
    case (.circleChange, .middlePad): "Pad along the thumb-side seam."
    case (.circleChange, .ringSide): "Pad along the pinky-side seam. A principal contact here."
    case (.circleChange, .thumbPad):
      "Wrapped around the lower thumb-side surface, closing the loop."
    case (.circleChange, .pinky): "Wrapped lightly around the far side to stabilise."
    case (.circleChange, .palm): "Let the ball settle comfortably into the hand."
    case (.circleChange, .wrist): "Wrist guidance is not specified by the source."
    case (.slider, .thumbPad):
      "Underneath and opposite the middle finger, slightly off centre, no hard pinch."
    case (.slider, .wrist): "Release decides whether this behaves like a slider."
    case (.slider, .ringSide): "Curled against the surface below the middle finger."
    case (_, .ringSide): "Side of the finger curled against the ball for light support."
    case (_, .pinky): "Relaxed beside the ring finger, clear of the ball."
    case (_, .thumbPad): "Fleshy pad underneath, on smooth leather, opposite the two upper fingers."
    case (_, .palm): "Do not bury the ball. Leave a small gap."
    case (_, .wrist): "Stay behind the ball."
    }
  }
}

/// Step 4 supplies numeric severities under exact zone strings. No pressure-to-severity conversion.
public struct GripSeverityMap: Sendable, Equatable, Codable {
  public let values: [String: Double]
  public init(_ values: [String: Double]) {
    self.values = values.filter { GripZoneID(rawValue: $0.key) != nil && $0.value.isFinite }
      .mapValues { min(1, max(0, $0)) }
  }
  public subscript(_ zone: GripZoneID) -> Double? { values[zone.rawValue] }
  public init(from decoder: Decoder) throws { self.init(try [String: Double](from: decoder)) }
  public func encode(to encoder: Encoder) throws { try values.encode(to: encoder) }
  public static let sample = GripSeverityMap([
    "index-pad": 0.12, "middle-pad": 0.35, "ring-side": 0.1, "pinky": 0.15, "thumb-pad": 0.62,
    "palm": 0.3, "wrist": 0.85,
  ])
}
public enum GripSeverityBand: String, Sendable {
  case green, yellow, red
  public static func band(_ value: Double?) -> Self? {
    guard let value, value.isFinite else { return nil }
    return value < 0.2 ? .green : value < 0.5 ? .yellow : .red
  }
  public var label: String {
    switch self {
    case .green: "Low"
    case .yellow: "Review"
    case .red: "High"
    }
  }
}
