import Foundation

public enum ThrowSource: String, Codable, Sendable { case manual, sample }

public struct ThrowDraft: Codable, Sendable, Identifiable, Equatable {
  public var id: String
  public var velocityMph = ""
  public var totalSpinRpm = ""
  public var spinDirectionClock = ""
  public var spinEfficiencyPercent = ""
  public var gyroDegree = ""
  public var horizontalBreakInches = ""
  public var verticalBreakInches = ""
  public var releaseHeightFeet = ""
  public var rapsodoScore = ""

  public init(source: ThrowSource = .manual) {
    id = "\(source == .sample ? "sample-" : "")throw-\(UUID().uuidString)"
  }
}

public struct ThrowSessionDraft: Codable, Sendable, Equatable {
  public var sessionId: String
  public let source: ThrowSource
  public var rows: [ThrowDraft]

  public init(source: ThrowSource = .manual) {
    self.source = source
    sessionId = "\(source == .sample ? "sample-" : "")session-\(UUID().uuidString)"
    rows = [ThrowDraft(source: source)]
  }

  public static func sample() -> Self {
    var session = Self(source: .sample)
    session.rows = [
      ["82.4", "2180", "12:30", "84", "18.6", "13.8", "5.8"],
      ["83.1", "2220", "12:40", "86", "18.2", "14.1", "5.7"],
      ["81.8", "2140", "12:20", "83", "19.0", "13.5", "5.8"],
    ].map { values in
      var row = ThrowDraft(source: .sample)
      row.velocityMph = values[0]
      row.totalSpinRpm = values[1]
      row.spinDirectionClock = values[2]
      row.spinEfficiencyPercent = values[3]
      row.horizontalBreakInches = values[4]
      row.verticalBreakInches = values[5]
      row.releaseHeightFeet = values[6]
      return row
    }
    return session
  }
}

public struct ThrowMeasurements: Codable, Sendable, Equatable {
  public let velocityMph: Double
  public let totalSpinRpm: Double
  public let spinDirectionClock: Double
  public let spinEfficiencyPercent: Double?
  public let gyroDegree: Double?
  public let horizontalBreakInches: Double?
  public let verticalBreakInches: Double?
  public let releaseHeightFeet: Double
  public let rapsodoScore: Double?

  private enum CodingKeys: String, CodingKey {
    case velocityMph, totalSpinRpm, spinDirectionClock, spinEfficiencyPercent
    case gyroDegree, horizontalBreakInches, verticalBreakInches
    case releaseHeightFeet, rapsodoScore
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(velocityMph, forKey: .velocityMph)
    try c.encode(totalSpinRpm, forKey: .totalSpinRpm)
    try c.encode(spinDirectionClock, forKey: .spinDirectionClock)
    try c.encode(spinEfficiencyPercent, forKey: .spinEfficiencyPercent)
    try c.encode(gyroDegree, forKey: .gyroDegree)
    try c.encode(horizontalBreakInches, forKey: .horizontalBreakInches)
    try c.encode(verticalBreakInches, forKey: .verticalBreakInches)
    try c.encode(releaseHeightFeet, forKey: .releaseHeightFeet)
    try c.encode(rapsodoScore, forKey: .rapsodoScore)
  }
}

public struct ThrowRecord: Codable, Sendable, Identifiable {
  public let schemaVersion: String
  public let throwId: String
  public let sessionId: String
  public let pitchId: String
  public let recordedAt: String
  public let measurements: ThrowMeasurements
  public let source: ThrowSource
  public let extensions: [String: JSONValue]
  public var id: String { throwId }
}

public struct ThrowValidation: Decodable, Sendable {
  public let errors: [String: String]
  public let measurements: ThrowMeasurements?
}
