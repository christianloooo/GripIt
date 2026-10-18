import Foundation

public enum FocusSeverity: String, Codable, Sendable {
  case green, yellow, red
  public var numericValue: Double {
    switch self { case .green: 0.1; case .yellow: 0.35; case .red: 0.75 }
  }
  public var title: String {
    switch self { case .green: "Looks good"; case .yellow: "Review"; case .red: "Focus here" }
  }
}
public struct FocusZone: Codable, Sendable, Identifiable {
  public let zoneId: GripZoneID
  public let severity: FocusSeverity
  public let reason: String
  public let action: String?
  public let triggeringMeasurement: String
  public let confidence: Double
  public var id: GripZoneID { zoneId }
}
public struct FocusNextAction: Codable, Sendable {
  public let zoneId: GripZoneID?
  public let summary: String
  public var detail: String
  public var rewritten: Bool
  private enum CodingKeys: String, CodingKey { case zoneId, summary, detail, rewritten }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(zoneId, forKey: .zoneId)
    try c.encode(summary, forKey: .summary)
    try c.encode(detail, forKey: .detail)
    try c.encode(rewritten, forKey: .rewritten)
  }
}
public struct ThrowConsistency: Codable, Sendable {
  public let throwCount: Int
  public let velocitySpreadMph: Double
  public let totalSpinSpreadRpm: Double
  public let inconsistent: Bool
}
public struct FocusAssessment: Codable, Sendable, Identifiable {
  public let schemaVersion: String
  public let assessmentId: String
  public let gripPlanId: String
  public let throwIds: [String]
  public let ruleVersion: String
  public let classification: String
  public let zones: [FocusZone]
  public var nextAction: FocusNextAction
  public let confidence: Double
  public let unreachableZones: [GripZoneID]
  public let consistency: ThrowConsistency?
  public let prototypeAdvice: Bool
  public let extensions: [String: JSONValue]
  public var id: String { assessmentId }
  public var severityMap: GripSeverityMap {
    GripSeverityMap(Dictionary(uniqueKeysWithValues: zones.map { ($0.zoneId.rawValue, $0.severity.numericValue) }))
  }

  public var measuredSummary: String? { feedbackText("measured") }
  public var changeToTry: String? { feedbackText("change") }
  public var expectedMovement: String? { feedbackText("expect") }
  public var feedbackKind: String? { feedbackText("kind") }

  /// Main screens show actions; the original measurements remain in Details.
  public var primaryAction: String {
    switch feedbackKind {
    case "change":
      return zones.first { $0.severity == .red }?.action
        ?? "Add the missing readings before changing your grip."
    case "fit": return "Try another grip or check your hand scan before making changes."
    case "baseline": return "Record your fastball first so we can compare your changeup."
    case "drift": return "Keep your release point steady before changing your grip."
    case "on-target": return "Keep this grip and record another throw."
    default: return "Add your throw readings to see what to try next."
    }
  }

  /// A rule can name two fingers. Show that adjustment once, with both
  /// fingers still independently selectable on the model.
  public var secondaryActions: [FocusZone] {
    guard feedbackKind == "change" else { return [] }
    var seen = Set([primaryAction])
    return zones.filter { zone in
      guard zone.severity == .yellow, let action = zone.action else { return false }
      return seen.insert(action).inserted
    }
  }

  public func action(for zone: GripZoneID) -> String {
    guard feedbackKind == "change" || feedbackKind == "on-target" else { return primaryAction }
    guard let finding = zones.first(where: { $0.zoneId == zone }) else {
      return "No change is suggested for this area."
    }
    if finding.severity == .green { return "Keep this position for your next throw." }
    return finding.action ?? "Add the missing readings before changing this part of your grip."
  }

  private func feedbackText(_ key: String) -> String? {
    guard case .object(let feedback) = extensions["gripFeedback"],
      case .string(let text) = feedback[key], !text.isEmpty else { return nil }
    return text
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, assessmentId, gripPlanId, throwIds, ruleVersion, classification
    case zones, nextAction, confidence, unreachableZones, consistency, prototypeAdvice, extensions
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(schemaVersion, forKey: .schemaVersion)
    try c.encode(assessmentId, forKey: .assessmentId)
    try c.encode(gripPlanId, forKey: .gripPlanId)
    try c.encode(throwIds, forKey: .throwIds)
    try c.encode(ruleVersion, forKey: .ruleVersion)
    try c.encode(classification, forKey: .classification)
    try c.encode(zones, forKey: .zones)
    try c.encode(nextAction, forKey: .nextAction)
    try c.encode(confidence, forKey: .confidence)
    try c.encode(unreachableZones, forKey: .unreachableZones)
    try c.encode(consistency, forKey: .consistency)
    try c.encode(prototypeAdvice, forKey: .prototypeAdvice)
    try c.encode(extensions, forKey: .extensions)
  }
}
