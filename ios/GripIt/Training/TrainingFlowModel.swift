import Foundation
import GripItScannerCore
import SwiftUI

/// The solved grip plus everything the scene derives from it.
///
/// `render` is built on the solving task, not on the main thread, so switching
/// pitch reuses it instead of rebuilding the zone surface and shading weights.
struct StudioFit: Sendable {
  let render: GripRenderState
  var pose: GripPose { render.pose }
  var plan: GripPlan { render.plan }
}

@MainActor
final class GripStudioSession: ObservableObject {
  let profile: HandProfile
  private let cache = SessionTaskCache<PitchGrip, StudioFit>()
  private var trainingSessions: [PitchGrip: TrainingFlowModel] = [:]

  init(profile: HandProfile) { self.profile = profile }

  func fitted(_ pitch: PitchGrip) async throws -> StudioFit {
    let profile = profile
    return try await cache.value(for: pitch) {
      let pose = try GripPoseSolver.solve(profile: profile, pitch: pitch)
      // Derive the scene's data here, on this detached task, so revisiting a
      // pitch reuses it instead of rebuilding it while the view updates.
      return StudioFit(render: try GripRenderState(pose: pose))
    }
  }

  func training(for fit: StudioFit) -> TrainingFlowModel {
    if let existing = trainingSessions[fit.pose.pitch] { return existing }
    let model = TrainingFlowModel(profile: profile, fit: fit) { [weak self] source in
      self?.fastballRecords(source: source) ?? []
    }
    trainingSessions[fit.pose.pitch] = model
    return model
  }

  private func fastballRecords(source: ThrowSource) -> [ThrowRecord] {
    [PitchGrip.fourSeam, .twoSeam].flatMap { pitch -> [ThrowRecord] in
      guard let model = trainingSessions[pitch], model.draft.source == source,
        model.hasEntries
      else { return [] }
      // Validate the current draft, so edits and invalid rows cannot reuse stale data.
      return (try? NativeFocusEngine.records(model.draft, pitch: pitch,
        profileId: profile.profileId)) ?? []
    }
  }
}

@MainActor
final class TrainingFlowModel: ObservableObject {
  let profile: HandProfile
  let fit: StudioFit
  let gripPlanId: String
  @Published var draft = ThrowSessionDraft()
  @Published var photos = SessionThrowPhoto.bundled
  @Published private(set) var errors: [String: [String: String]] = [:]
  @Published private(set) var message: String?
  private let baselineRecords: @MainActor (ThrowSource) -> [ThrowRecord]
  var pitch: PitchGrip { fit.pose.pitch }
  var usesSampleHand: Bool { profile.capture.method.localizedCaseInsensitiveContains("sample") }

  init(profile: HandProfile, fit: StudioFit,
    baselineRecords: @escaping @MainActor (ThrowSource) -> [ThrowRecord] = { _ in [] }) {
    self.profile = profile
    self.fit = fit
    self.baselineRecords = baselineRecords
    gripPlanId = "\(profile.profileId)-\(fit.pose.pitch.rawValue)-\(fit.pose.id.uuidString)"
  }

  func addThrow() {
    draft.rows.append(ThrowDraft(source: draft.source))
  }

  func removeThrow(_ id: String) {
    guard draft.rows.count > 1 else { return }
    draft.rows.removeAll { $0.id == id }
    errors[id] = nil
  }

  func replaceDraft(sample: Bool) {
    draft = sample ? .sample() : ThrowSessionDraft()
    errors = [:]
    message = nil
  }

  var hasEntries: Bool {
    draft.rows.contains {
      ![
        $0.velocityMph, $0.totalSpinRpm, $0.spinDirectionClock,
        $0.spinEfficiencyPercent, $0.gyroDegree, $0.horizontalBreakInches,
        $0.verticalBreakInches, $0.releaseHeightFeet, $0.rapsodoScore,
      ].allSatisfy(\.isEmpty)
    }
  }

  func assessment() -> FocusAssessment? {
    errors = [:]
    message = nil
    do {
      for row in draft.rows {
        let result = try NativeFocusEngine.validate(row)
        if !result.errors.isEmpty { errors[row.id] = result.errors }
      }
      guard errors.isEmpty else {
        message = "Check the highlighted fields."
        return nil
      }
      let records = try NativeFocusEngine.records(draft, pitch: pitch, profileId: profile.profileId)
      let result = try NativeFocusEngine.assess(
        pitch: pitch, records: records,
        zones: fit.plan.zones, gripPlanId: gripPlanId,
        baseline: baselineRecords(draft.source), handedness: profile.handedness)
      return result
    } catch {
      message = error.localizedDescription
      return nil
    }
  }


}

struct TrainingStepLabel: View {
  let step: Int
  var body: some View {
    HStack(spacing: 8) {
      Text("STEP \(step) OF 4").font(.caption2.weight(.semibold))
      Spacer()
      ForEach(1...4, id: \.self) { index in
        Capsule().fill(index <= step ? Color.mint : Color.white.opacity(0.2))
          .frame(width: 22, height: 4)
      }
    }
    .foregroundStyle(.secondary)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Step \(step) of 4")
  }
}
