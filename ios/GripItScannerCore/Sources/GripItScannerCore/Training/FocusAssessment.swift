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
