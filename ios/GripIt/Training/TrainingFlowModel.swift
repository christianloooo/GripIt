import Foundation
import GripItScannerCore
import SwiftUI

struct StudioFit: Sendable {
  let pose: GripPose
  let plan: GripPlan
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
      return StudioFit(pose: pose, plan: GripPlan(pose: pose))
    }
  }

  func training(for fit: StudioFit) -> TrainingFlowModel {
    if let existing = trainingSessions[fit.pose.pitch] { return existing }
    let model = TrainingFlowModel(profile: profile, fit: fit)
    trainingSessions[fit.pose.pitch] = model
    return model
  }
}

@MainActor
final class TrainingFlowModel: ObservableObject {
  let profile: HandProfile
  let fit: StudioFit
  let gripPlan: FocusGripPlan
  let client: CoachingClient
  @Published var draft = ThrowSessionDraft()
  @Published private(set) var errors: [String: [String: String]] = [:]
  @Published private(set) var message: String?
  private var assessedRecords: [ThrowRecord]?
  var pitch: PitchGrip { fit.pose.pitch }
  var usesSampleHand: Bool { profile.capture.method.localizedCaseInsensitiveContains("sample") }

  init(profile: HandProfile, fit: StudioFit) {
    self.profile = profile
    self.fit = fit
    let planId = "\(profile.profileId)-\(fit.pose.pitch.rawValue)-\(fit.pose.id.uuidString)"
    gripPlan = FocusGripPlan(
      profileId: profile.profileId, pitch: fit.pose.pitch,
      zones: fit.plan.zones, gripPlanId: planId)
    let value = Bundle.main.object(forInfoDictionaryKey: "GripItAPIBaseURL") as? String
    let url = value.flatMap { $0.contains("$(") ? nil : URL(string: $0) }
    client = CoachingClient(baseURL: url)
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
        $0.velocityMph, $0.totalSpinRpm, $0.spinDirectionClock, $0.spinValue,
        $0.releaseHeightFeet, $0.rapsodoScore,
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
        zones: fit.plan.zones, gripPlanId: gripPlan.gripPlanId)
      assessedRecords = records
      return result
    } catch {
      message = error.localizedDescription
      return nil
    }
  }

  func context(for assessment: FocusAssessment) -> CoachingContext {
    return CoachingContext(profile: profile, plan: gripPlan, assessment: assessment,
      records: assessedRecords)
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
