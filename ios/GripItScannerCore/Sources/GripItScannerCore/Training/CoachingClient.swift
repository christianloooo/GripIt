import Foundation
import CryptoKit

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
  public let records: [ThrowRecord]?
  private enum CodingKeys: String, CodingKey { case profile, plan, assessment; case records = "throws" }
  public init(profile: HandProfile, plan: FocusGripPlan, assessment: FocusAssessment,
    records: [ThrowRecord]? = nil) {
    self.profile = profile; self.plan = plan; self.assessment = assessment
    self.records = records
  }
}
public struct CoachReply: Decodable, Sendable {
  public let detail: String
  public let rewritten: Bool
  public let fit: String?
  public let reason: String?
  public var fitReason: String? = nil
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
  private let responses = CoachingResponseCache()
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
      let result: CoachReply = try await post("coach", body: context, timeout: 10) {
        $0.rewritten && $0.fit != nil
      }
      guard !result.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClientError.invalid }
      return result
    } catch {
      return CoachReply(detail: context.assessment.nextAction.detail, rewritten: false, fit: nil, reason: reason(error))
    }
  }

  public func ask(_ question: String, context: CoachingContext) async -> AskReply {
    struct Body: Encodable {
      let assessment: FocusAssessment; let profile: HandProfile; let plan: FocusGripPlan; let question: String
      let records: [ThrowRecord]?
      private enum CodingKeys: String, CodingKey { case assessment, profile, plan, question; case records = "throws" }
    }
    do {
      let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
      guard (3...300).contains(trimmed.count) else { throw ClientError.invalid }
      let result: AskReply = try await post("ask", body: Body(assessment: context.assessment,
        profile: context.profile, plan: context.plan, question: trimmed, records: context.records), timeout: 15) { $0.answered }
      guard !result.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClientError.invalid }
      return result
    } catch {
      return AskReply(answer: "AI coaching is unavailable right now. Your feedback above is still available.",
        answered: false, reason: reason(error))
    }
  }

  private func post<Body: Encodable, Output: Decodable & Sendable>(
    _ path: String, body: Body, timeout: TimeInterval,
    cacheable: @escaping @Sendable (Output) -> Bool
  ) async throws -> Output {
    guard let baseURL else { throw ClientError.notConfigured }
    var request = URLRequest(url: baseURL.appendingPathComponent("api").appendingPathComponent(path))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = timeout
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    request.httpBody = try encoder.encode(body)
    let key = "\(request.url!.absoluteString):\(SHA256.hash(data: request.httpBody!))"
    let transport = transport
    let preparedRequest = request
    let data = try await responses.value(for: key, work: {
      let (data, status) = try await transport(preparedRequest)
      guard (200..<300).contains(status) else { throw ClientError.http(status) }
      _ = try JSONDecoder().decode(Output.self, from: data)
      return data
    }, cacheable: { data in
      guard let output = try? JSONDecoder().decode(Output.self, from: data) else { return false }
      return cacheable(output)
    })
    return try JSONDecoder().decode(Output.self, from: data)
  }
  private enum ClientError: Error { case notConfigured, invalid, http(Int) }
  private func reason(_ error: Error) -> String {
    if case ClientError.notConfigured = error { return "not-configured" }
    if case ClientError.http(let status) = error { return "http-\(status)" }
    if (error as? URLError)?.code == .timedOut { return "timeout" }
    if let code = (error as? URLError)?.code {
      switch code {
      case .cannotFindHost, .dnsLookupFailed: return "host-not-found"
      case .cannotConnectToHost, .networkConnectionLost: return "cannot-connect"
      case .notConnectedToInternet: return "offline-or-local-network-denied"
      default: break
      }
    }
    return "unavailable"
  }
}

private actor CoachingResponseCache {
  private struct Entry { let data: Data; let expires: Date }
  private var values: [String: Entry] = [:]
  private var order: [String] = []
  private var pending: [String: Task<Data, Error>] = [:]

  func value(for key: String, work: @escaping @Sendable () async throws -> Data,
    cacheable: @escaping @Sendable (Data) -> Bool) async throws -> Data {
    if let entry = values[key], entry.expires > Date() { return entry.data }
    values[key] = nil
    order.removeAll { $0 == key }
    if let task = pending[key] { return try await task.value }
    guard pending.count < 8 else { throw URLError(.resourceUnavailable) }
    let task = Task { try await work() }
    pending[key] = task
    defer { pending[key] = nil }
    let data = try await task.value
    if cacheable(data) {
      values[key] = Entry(data: data, expires: Date().addingTimeInterval(600))
      order.append(key)
      while order.count > 32 { values[order.removeFirst()] = nil }
    }
    return data
  }
}
