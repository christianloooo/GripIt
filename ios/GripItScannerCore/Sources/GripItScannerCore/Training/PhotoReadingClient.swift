import Foundation

public enum PhotoReadingError: Error, LocalizedError, Sendable, Equatable {
  case notConfigured, invalidPhoto, invalidResponse, signInRequired, quotaExceeded, timedOut, unreadable, unavailable

  public var errorDescription: String? {
    switch self {
    case .notConfigured: "Photo reading is not connected. Enter the readings below."
    case .invalidPhoto: "Choose a JPEG or PNG photo smaller than 4 MiB."
    case .invalidResponse: "These readings could not be checked. Try again or enter them below."
    case .signInRequired: "Sign in again to read this photo. Your entries are still here."
    case .quotaExceeded: "You have used today's photo scans. Enter readings yourself or view your plan."
    case .timedOut: "Photo reading took too long. Try again or enter the readings below."
    case .unreadable: "We could not read this photo clearly. Try another photo or enter the readings below."
    case .unavailable: "Photo reading is unavailable. Check your connection or enter the readings below."
    }
  }
}

public struct PhotoReadings: Decodable, Sendable {
  public let velocityMph: Double?
  public let totalSpinRpm: Double?
  public let spinDirectionClock: String?
  public let spinEfficiencyPercent: Double?
  public let gyroDegree: Double?
  public let horizontalBreakInches: Double?
  public let verticalBreakInches: Double?
  public let releaseHeightFeet: Double?
  public let rapsodoScore: Double?

  private enum CodingKeys: String, CodingKey {
    case velocityMph, totalSpinRpm, spinDirectionClock, spinEfficiencyPercent, gyroDegree
    case horizontalBreakInches, verticalBreakInches, releaseHeightFeet, rapsodoScore
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    // Null is valid; omitted keys indicate an incompatible server response.
    velocityMph = try c.decode(Double?.self, forKey: .velocityMph)
    totalSpinRpm = try c.decode(Double?.self, forKey: .totalSpinRpm)
    spinDirectionClock = try c.decode(String?.self, forKey: .spinDirectionClock)
    spinEfficiencyPercent = try c.decode(Double?.self, forKey: .spinEfficiencyPercent)
    gyroDegree = try c.decode(Double?.self, forKey: .gyroDegree)
    horizontalBreakInches = try c.decode(Double?.self, forKey: .horizontalBreakInches)
    verticalBreakInches = try c.decode(Double?.self, forKey: .verticalBreakInches)
    releaseHeightFeet = try c.decode(Double?.self, forKey: .releaseHeightFeet)
    rapsodoScore = try c.decode(Double?.self, forKey: .rapsodoScore)
  }

  fileprivate func draft(source: ThrowSource) -> ThrowDraft {
    func text(_ value: Double?) -> String {
      guard let value, value.isFinite else { return "" }
      let string = String(value)
      return string.hasSuffix(".0") ? String(string.dropLast(2)) : string
    }
    var row = ThrowDraft(source: source)
    row.velocityMph = text(velocityMph)
    row.totalSpinRpm = text(totalSpinRpm)
    row.spinDirectionClock = spinDirectionClock ?? ""
    row.spinEfficiencyPercent = text(spinEfficiencyPercent)
    row.gyroDegree = text(gyroDegree)
    row.horizontalBreakInches = text(horizontalBreakInches)
    row.verticalBreakInches = text(verticalBreakInches)
    row.releaseHeightFeet = text(releaseHeightFeet)
    row.rapsodoScore = text(rapsodoScore)
    return row
  }
}

public struct PhotoReadResponse: Decodable, Sendable {
  public let schemaVersion: String
  public let model: String
  public let requestId: String
  public let readings: PhotoReadings
  public let warnings: [String]
  public func makeDraft(source: ThrowSource) -> ThrowDraft { readings.draft(source: source) }
}

public struct PhotoReadingClient: Sendable {
  public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
  private let baseURL: URL
  private let bearerToken: String?
  private let transport: Transport

  public init(baseURL: URL, bearerToken: String? = nil, transport: Transport? = nil) {
    self.baseURL = baseURL
    self.bearerToken = bearerToken
    self.transport = transport ?? { request in
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let response = response as? HTTPURLResponse else { throw PhotoReadingError.invalidResponse }
      return (data, response)
    }
  }

  public func read(image: Data, contentType: String, requestId: String) async throws -> PhotoReadResponse {
    try Task.checkCancellation()
    guard ["http", "https"].contains(baseURL.scheme?.lowercased() ?? ""), baseURL.host != nil,
      baseURL.user == nil, baseURL.password == nil else { throw PhotoReadingError.notConfigured }
    guard !image.isEmpty, image.count <= 4 * 1024 * 1024,
      ["image/jpeg", "image/png"].contains(contentType) else { throw PhotoReadingError.invalidPhoto }
    var request = URLRequest(url: baseURL.appendingPathComponent("api/photos/read"))
    request.httpMethod = "POST"
    request.timeoutInterval = 45
    request.httpBody = image
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(requestId, forHTTPHeaderField: "Idempotency-Key")
    if let bearerToken { request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization") }
    do {
      let (data, http) = try await transport(request)
      try Task.checkCancellation()
      switch http.statusCode {
      case 200: break
      case 401: throw PhotoReadingError.signInRequired
      case 429:
        let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let error = envelope?["error"] as? [String: Any]
        throw error?["code"] as? String == "quota_exceeded" ? PhotoReadingError.quotaExceeded : .unavailable
      case 504: throw PhotoReadingError.timedOut
      case 502: throw PhotoReadingError.unreadable
      default: throw PhotoReadingError.unavailable
      }
      guard data.count <= 128 * 1024,
        let result = try? JSONDecoder().decode(PhotoReadResponse.self, from: data),
        result.schemaVersion == "1.0.0", result.model == "perceptron-mk1.5", result.requestId == requestId
      else { throw PhotoReadingError.invalidResponse }
      return result
    } catch is CancellationError { throw CancellationError() }
    catch let error as URLError {
      if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
      throw error.code == .timedOut ? PhotoReadingError.timedOut : .unavailable
    } catch let error as PhotoReadingError { throw error }
    catch { throw PhotoReadingError.unavailable }
  }
}
