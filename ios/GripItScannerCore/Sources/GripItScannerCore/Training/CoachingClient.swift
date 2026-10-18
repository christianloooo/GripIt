import Foundation

/// Adapter for the existing Step 4 API. Geometry is deliberately opaque to AI.
public struct FocusGripPlan: Encodable, Sendable {
  public let schemaVersion = "1.0.0"
  public let gripPlanId: String
  public let handProfileId: String
  public let pitchId: String
  public let instructionZones: [GripZonePlan]
  public let ballTransform = JSONValue.null
  public let jointTransforms = JSONValue.null
  public let contacts = JSONValue.null
  public let extensions: [String: JSONValue] = [:]
  public struct Fit: Encodable, Sendable {
    // The native solver supplies geometric constraints, not a numeric fit probability.
    public let confidence = JSONValue.null
    public let unresolved: [String]
  }
  public let fit: Fit

  public init(profileId: String, pitch: PitchGrip, zones: [GripZonePlan], gripPlanId: String) {
    self.gripPlanId = gripPlanId
    handProfileId = profileId
    pitchId = pitch.rawValue
    instructionZones = zones
    fit = Fit(unresolved: zones.filter { $0.reach != .comfortable }.map { "\($0.title): \($0.reach.rawValue)" })
  }
}

public struct CoachingContext: Encodable, Sendable {
  public let profile: HandProfile
  public let plan: FocusGripPlan
  public let assessment: FocusAssessment
  public init(profile: HandProfile, plan: FocusGripPlan, assessment: FocusAssessment) {
    self.profile = profile; self.plan = plan; self.assessment = assessment
  }
}
public struct CoachReply: Decodable, Sendable {
  public let detail: String
  public let rewritten: Bool
  public let fit: String?
  public let reason: String?
}
public struct AskReply: Decodable, Sendable {
  public let answer: String
  public let answered: Bool
  public let reason: String?
}

public struct CoachingClient: Sendable {
  public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)
  private let baseURL: URL?
  private let transport: Transport
  public var isConfigured: Bool { baseURL != nil }

  public init(baseURL: URL?, transport: @escaping Transport = { request in
    let (data, response) = try await URLSession.shared.data(for: request)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
  }) {
    self.baseURL = baseURL.flatMap { url in
      guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
      return url
    }
    self.transport = transport
  }

  public func coach(_ context: CoachingContext) async -> CoachReply {
    do {
      let result: CoachReply = try await post("coach", body: context, timeout: 8)
      guard !result.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClientError.invalid }
      return result
    } catch {
      return CoachReply(detail: context.assessment.nextAction.detail, rewritten: false, fit: nil, reason: reason(error))
    }
  }

  public func ask(_ question: String, context: CoachingContext) async -> AskReply {
    struct Body: Encodable {
      let assessment: FocusAssessment; let profile: HandProfile; let plan: FocusGripPlan; let question: String
    }
    do {
      let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
      guard (3...300).contains(trimmed.count) else { throw ClientError.invalid }
      let result: AskReply = try await post("ask", body: Body(assessment: context.assessment,
        profile: context.profile, plan: context.plan, question: trimmed), timeout: 15)
      guard !result.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClientError.invalid }
      return result
    } catch {
      return AskReply(answer: "AI coaching is unavailable right now. Your feedback above is still available.",
        answered: false, reason: reason(error))
    }
  }

  private func post<Body: Encodable, Output: Decodable>(_ path: String, body: Body, timeout: TimeInterval) async throws -> Output {
    guard let baseURL else { throw ClientError.notConfigured }
    var request = URLRequest(url: baseURL.appendingPathComponent("api").appendingPathComponent(path))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = timeout
    request.httpBody = try JSONEncoder().encode(body)
    let (data, status) = try await transport(request)
    guard (200..<300).contains(status) else { throw ClientError.http(status) }
    return try JSONDecoder().decode(Output.self, from: data)
  }
  private enum ClientError: Error { case notConfigured, invalid, http(Int) }
  private func reason(_ error: Error) -> String {
    if case ClientError.notConfigured = error { return "not-configured" }
    if case ClientError.http(let status) = error { return "http-\(status)" }
    if (error as? URLError)?.code == .timedOut { return "timeout" }
    return "unavailable"
  }
}
