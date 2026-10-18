import Foundation

/// The baseball version of rapsodo1, using readings from the original
/// baseball capture. Unknown photos never receive these sample values.
public enum RapsodoPhotoFixture: String, CaseIterable, Identifiable, Sendable {
  case baseball = "rapsodo1"

  public var id: String { rawValue }
  public var title: String { "Rapsodo photo" }
  public var imageURL: URL? { Bundle.module.url(forResource: rawValue, withExtension: "png") }
  public var previewURL: URL? { imageURL }

  public func makeDraft() -> ThrowDraft {
    var draft = ThrowDraft(source: .sample)
    draft.velocityMph = "77.3"
    draft.totalSpinRpm = "1642"
    draft.spinDirectionClock = "01:56"
    draft.spinEfficiencyPercent = "93.8"
    draft.horizontalBreakInches = "18.6"
    draft.verticalBreakInches = "13.8"
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
