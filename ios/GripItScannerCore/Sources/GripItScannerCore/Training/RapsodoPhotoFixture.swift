import Foundation

/// Bundled captures with readings transcribed from the visible screenshot.
/// Unknown photos never receive these readings.
public enum RapsodoPhotoFixture: String, CaseIterable, Identifiable, Sendable {
  case softball = "rapsodo1"
  case baseball = "rapsodo2"

  public var id: String { rawValue }
  public var title: String { self == .softball ? "Softball capture" : "Baseball capture" }
  public var imageURL: URL? { Bundle.module.url(forResource: rawValue, withExtension: "webp") }
  /// PNG companion for reliable native image decoding on every supported device.
  public var previewURL: URL? { Bundle.module.url(forResource: rawValue, withExtension: "png") }

  public func makeDraft() -> ThrowDraft {
    var draft = ThrowDraft(source: .sample)
    switch self {
    case .softball:
      draft.velocityMph = "43.4"
      draft.totalSpinRpm = "1077"
      draft.spinDirectionClock = "06:48"
      draft.spinEfficiencyPercent = "95.0"
      draft.gyroDegree = "-18.2"
    case .baseball:
      draft.velocityMph = "77.3"
      draft.totalSpinRpm = "1642"
      draft.spinDirectionClock = "01:56"
      draft.spinEfficiencyPercent = "93.8"
      draft.horizontalBreakInches = "18.6"
      draft.verticalBreakInches = "13.8"
    }
    // Release height, score, and every other absent reading stay empty.
    // Active spin is derived by the measurement contract, not copied as total spin.
    return draft
  }

  /// Recognition is deliberately exact. Similar images and edited screenshots
  /// remain manual entries rather than inheriting sample measurements.
  public static func matching(_ data: Data) -> Self? {
    allCases.first { fixture in
      [fixture.imageURL, fixture.previewURL].compactMap { $0 }.contains { url in
        (try? Data(contentsOf: url)) == data
      }
    }
  }
}
