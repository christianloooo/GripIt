import Foundation
import simd

public enum GripFinger: String, CaseIterable, Codable, Sendable {
  case thumb, index, middle, ring, pinky
  public var title: String { rawValue.capitalized }
  public var jointNames: [String] {
    let prefix = self == .thumb ? "thumb" : "\(rawValue)-finger"
    return self == .thumb
      ? [
        "\(prefix)-metacarpal", "\(prefix)-phalanx-proximal", "\(prefix)-phalanx-distal",
        "\(prefix)-tip",
      ]
      : [
        "\(prefix)-phalanx-proximal", "\(prefix)-phalanx-intermediate", "\(prefix)-phalanx-distal",
        "\(prefix)-tip",
      ]
  }
  public var landmarkRoot: String { self == .thumb ? "thumbCMC" : "\(rawValue)MCP" }
  func measurement(_ profile: HandProfile) -> FingerMeasurements {
    let f = profile.measurements.fingers
    return switch self {
    case .thumb: f.thumb
    case .index: f.index
    case .middle: f.middle
    case .ring: f.ring
    case .pinky: f.pinky
    }
  }
}
public struct GripHandAsset: Decodable, Sendable {
  public static var licenseText: String {
    guard let url = Bundle.module.url(forResource: "grip-hand-license", withExtension: "txt"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return "See bundled grip-hand-license.txt" }
    return text
  }
  public struct Joint: Decodable, Sendable {
    public let name: String
    public let position: [Double]
  }
  public var palmReferenceThickness: Double {
    let section = vertices.filter { abs($0[0]) < 12 && (30...50).contains($0[1]) }.map { $0[2] }
    return max(1, (section.max() ?? 40) - (section.min() ?? -14))
  }
  public let vertices: [[Double]]
  public let weights: [[Double]]
  public let joints: [Joint]
  public let indices: [UInt32]
  public let authoredFingerRadii: [String: Double]?
  public let preserveAuthoredAnatomy: Bool?
  private static let cached: Result<Self, Error> = Result { try GripResources.decode("grip-hand") }
  public static func load() throws -> Self { try cached.get() }
}
public struct GripBallAsset: Decodable, Sendable {
  public struct Seam: Decodable, Sendable {
    public let position: [Double]
    public let tangent: [Double]
  }
  public let vertices: [[Double]]
  public let normals: [[Double]]?
  public let normalTexture: String?
  public let materialTexture: String?
  public let sourceSHA256: String?
  public let variant: String?
  public let radiusMm: Double?
  public let uv: [[Double]]
  public let indices: [UInt32]
  public let texture: String
  public let seams: [Seam]
  private static let cached: Result<Self, Error> = Result {
    try GripResources.decode("grip-baseball")
  }
  public static func load() throws -> Self { try cached.get() }
  public var normalTextureURL: URL? { normalTexture.flatMap(resourceURL) }
  public var materialTextureURL: URL? { materialTexture.flatMap(resourceURL) }
  private func resourceURL(_ name: String) -> URL? {
    Bundle.module.url(
      forResource: (name as NSString).deletingPathExtension,
      withExtension: (name as NSString).pathExtension)
  }
  public var textureURL: URL? {
    Bundle.module.url(
      forResource: (texture as NSString).deletingPathExtension,
      withExtension: (texture as NSString).pathExtension)
  }
}
/// Continuous, constant-radius threads recovered from the original ball's UV strokes.
public struct GripBallStitchAsset: Decodable, Sendable {
  public let vertices: [[Double]]
  public let normals: [[Double]]
  public let indices: [UInt32]
  public let stitchCount: Int
  public let threadRadiusMm: Double
  public let threadCenterRadiusMm: Double
  public let sourceSHA256: String
  private static let cached: Result<Self, Error> = Result { try GripResources.decode("grip-baseball-stitches") }
  public static func load() throws -> Self { try cached.get() }
}
enum GripResources {
  static func decode<T: Decodable>(_ name: String) throws -> T {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
      throw GripError.invalid("Missing bundled \(name) model.")
    }
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
  }
}
public enum GripError: LocalizedError {
  case invalid(String)
  public var errorDescription: String? {
    switch self {
    case .invalid(let reason): reason
    }
  }
}
func gv(_ a: [Double]) -> SIMD3<Double> { SIMD3(a[0], a[1], a[2]) }
func unit(_ v: SIMD3<Double>) -> SIMD3<Double> {
  simd_length(v) > 1e-9 ? simd_normalize(v) : SIMD3(0, 1, 0)
}
