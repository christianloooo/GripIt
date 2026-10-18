import Foundation

public enum PitchGrip: String, CaseIterable, Identifiable, Codable, Sendable {
  case fourSeam = "four-seam"
  case twoSeam = "two-seam"
  case slider
  case circleChange = "changeup"
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .fourSeam: "Four-seam fastball"
    case .twoSeam: "Two-seam fastball"
    case .slider: "Slider"
    case .circleChange: "Circle changeup"
    }
  }
  public var shortTitle: String {
    switch self {
    case .fourSeam: "4-seam"
    case .twoSeam: "2-seam"
    case .slider: "Slider"
    case .circleChange: "Changeup"
    }
  }
  public var upperContacts: [GripFinger] {
    zoneTemplates.filter { $0.placement?.region == .top }.compactMap { $0.zoneId.finger }
  }
  public func instruction(for finger: GripFinger) -> String {
    zoneTemplates.first { $0.zoneId.finger == finger }?.instruction ?? ""
  }

  public var orientation: String {
    switch self {
    case .fourSeam:
      "Horseshoe sideways: rounded end toward the thumb, opening toward the pinky. Upper pads cross the seams."
    case .twoSeam:
      "Narrow seam pair runs from wrist toward fingertips. Each upper pad follows its own seam."
    case .slider:
      "Begin at the narrow seam pair. Group the fingers at the pinky-side seam; middle on stitching, index on adjacent leather."
    case .circleChange:
      "Narrow seams follow middle and ring fingers. Index and thumb form a small, relaxed loop beside the ball."
    }
  }
  public var depth: String {
    self == .circleChange
      ? "Let the ball settle into the hand. Keep the loop relaxed."
      : self == .slider
        ? "Secure middle-finger contact, supported by the thumb; comfortable depth."
        : "Hold between the upper pads and thumb, with a little space from the palm."
  }
}
