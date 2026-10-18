import GripItScannerCore
import SwiftUI

struct FocusAssessmentView: View {
  @ObservedObject var model: TrainingFlowModel
  let assessment: FocusAssessment
  @Environment(\.dismiss) private var dismiss
  @State private var selectedZone: GripZoneID?
  @State private var camera: GripCamera = .threeQuarter
  @State private var reset = 0
  @State private var coaching: CoachReply?
  @State private var loadingCoach = false
  @State private var coachRequest = UUID()
  @State private var question = ""
  @State private var submittedQuestion: String?
  @State private var questionRequest = UUID()
  @State private var answer: AskReply?
  @State private var asking = false
  @State private var showPrototypeFlags = false
  @FocusState private var editingQuestion: Bool

  private var context: CoachingContext { model.context(for: assessment) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        TrainingStepLabel(step: 4)
        HStack {
          Text("Your throw review")
            .font(.title.bold())
          Spacer()
          if model.draft.source == .sample || model.usesSampleHand {
            Text("SAMPLE").font(.caption2.bold()).foregroundStyle(.mint)
          }
        }
        Text(model.pitch.title).font(.subheadline).foregroundStyle(.secondary)

        // This is the very same pose and plan captured in Step 2. No second solve.
        GripSceneView(
          pose: model.fit.pose, showContacts: false, camera: camera,
          reset: reset, gripPlan: model.fit.plan,
          zoneSeverity: showPrototypeFlags ? assessment.severityMap : nil,
          selectedZone: selectedZone, onZoneSelect: { selectedZone = $0 }
        )
        .frame(height: 330)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityLabel("Your \(model.pitch.title) grip with throw feedback")

        HStack {
          ForEach(GripCamera.allCases) { angle in
            Button(angle.title) {
              camera = angle
              reset += 1
            }
            .buttonStyle(.bordered).tint(camera == angle ? .mint : .gray)
            .lineLimit(1).minimumScaleFactor(0.65)
          }
        }.frame(maxWidth: .infinity)

        if !model.fit.plan.zones.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(model.fit.plan.zones) { zone in
                Button {
                  selectedZone = zone.zoneId
                } label: {
                  HStack(spacing: 6) {
                    Text(zone.zoneId.title)
                  }.padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .tint(selectedZone == zone.zoneId ? .mint : .gray)
                .accessibilityLabel(zone.zoneId.title)
                .accessibilityAddTraits(selectedZone == zone.zoneId ? .isSelected : [])
              }
            }
          }
        }

        if let selectedZone {
          VStack(alignment: .leading, spacing: 8) {
            Text(selectedZone.title).font(.headline)
            if let zone = model.fit.plan.zones.first(where: { $0.zoneId == selectedZone }) {
              Text(zone.instruction).font(.subheadline)
              if zone.reach != .comfortable {
                Text("Check this contact's fit before changing pressure.")
                  .font(.caption).foregroundStyle(.orange)
              }
            } else {
              Text("No assessment for this area.").font(.subheadline).foregroundStyle(.secondary)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        }

        VStack(alignment: .leading, spacing: 10) {
          Text("AI COACHING").font(.caption.bold()).foregroundStyle(.mint)
          if coaching?.rewritten == true {
            Text(coaching!.detail).font(.subheadline)
          } else if loadingCoach {
            HStack { ProgressView().controlSize(.small); Text("Reviewing your throws…") }
          } else {
            Text("Your throw data is ready. Retry coaching or review the prototype notes below.")
              .font(.subheadline).foregroundStyle(.secondary)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
          .padding(18).background(.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))

        if let fit = coaching?.fit, !fit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Your hand and this grip").font(.headline)
            Text(fit).font(.subheadline).foregroundStyle(.secondary)
          }
        }

        if !assessment.unreachableZones.isEmpty {
          Label(
            "Some contacts need a better fit. Review your grip before changing pressure.",
            systemImage: "hand.raised"
          ).font(.caption).foregroundStyle(.orange)
        }

        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("Ask about your result").font(.headline)
            Spacer()
            if loadingCoach { ProgressView().controlSize(.small) }
          }
          HStack(alignment: .bottom) {
            TextField("Why this finger?", text: $question, axis: .vertical)
              .lineLimit(1...4).textFieldStyle(.plain)
              .padding(12).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
              .focused($editingQuestion).submitLabel(.send).onSubmit(submitQuestion)
              .accessibilityLabel("Question about your result")
            Button(action: submitQuestion) {
              if asking {
                ProgressView().controlSize(.small)
              } else {
                Image(systemName: "arrow.up").font(.headline)
              }
            }
            .frame(minWidth: 44, minHeight: 44).buttonStyle(.borderedProminent).tint(.mint)
            .disabled(
              question.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || asking
                || !model.client.isConfigured
            )
            .accessibilityLabel("Ask AI coach")
          }
          .onChange(of: question) { _, value in
            if value.count > 300 { question = String(value.prefix(300)) }
          }
          if let answer { Text(answer.answer).font(.subheadline).foregroundStyle(.secondary) }
          if !model.client.isConfigured
            || (!loadingCoach && coaching != nil
              && (coaching?.rewritten != true || coaching?.fit == nil))
          {
            HStack {
              Text(connectionMessage(coaching?.reason ?? coaching?.fitReason)).font(.caption)
                .foregroundStyle(.secondary)
              if model.client.isConfigured {
                Button("Retry") { coachRequest = UUID() }.font(.caption)
              }
            }
          }
        }

        DisclosureGroup("Prototype rule notes") {
          VStack(alignment: .leading, spacing: 8) {
            Text(
              "\(assessment.throwIds.count) throws"
            )
            Toggle("Show prototype colors", isOn: $showPrototypeFlags)
            ForEach(Array(Set(assessment.zones.map(\.reason))).sorted(), id: \.self) { reason in
              Text(reason)
            }
            Text(assessment.nextAction.summary)
            Text(assessment.nextAction.detail)
            Text("Rules: \(assessment.ruleVersion)")
            if let consistency = assessment.consistency {
              Text(
                String(
                  format: "Velocity spread %.1f mph · Spin spread %.0f rpm",
                  consistency.velocitySpreadMph, consistency.totalSpinSpreadRpm))
              if consistency.inconsistent {
                Text("Throws varied. Record more before changing your grip.")
              }
            }
            Text(
              "These test rules do not measure finger faults. Their confidence values are not calibrated.")
          }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
        }
        if assessment.prototypeAdvice {
          Text("Prototype guidance. Not coach reviewed.").font(.caption2).foregroundStyle(
            .secondary)
        }
      }.padding(20)
    }
    .background(.black).preferredColorScheme(.dark).tint(.mint)
    .navigationTitle("Feedback").navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .safeAreaInset(edge: .bottom) {
      Button {
        model.addThrow()
        dismiss()
      } label: {
        Label("Record another throw", systemImage: "arrow.right")
          .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black)
      .padding(.horizontal, 20).padding(.vertical, 12).background(.ultraThinMaterial)
    }
    .onAppear {
      selectedZone = selectedZone ?? model.fit.plan.zones.first?.zoneId
    }
    .task(id: coachRequest) {
      loadingCoach = true
      let result = await model.client.coach(context)
      guard !Task.isCancelled else { return }
      coaching = result
      loadingCoach = false
    }
    .task(id: questionRequest) {
      guard let submittedQuestion else { return }
      let result = await model.client.ask(submittedQuestion, context: context)
      guard !Task.isCancelled else { return }
      answer = result
      asking = false
    }
  }

  private func submitQuestion() {
    let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.count >= 3, text.count <= 300, !asking, model.client.isConfigured else { return }
    editingQuestion = false
    asking = true
    answer = nil
    submittedQuestion = text
    questionRequest = UUID()
  }
  private func connectionMessage(_ reason: String?) -> String {
    switch reason {
    case "not-configured": return "AI server address is missing. This app needs a configured build."
    case "host-not-found", "cannot-connect": return "Can't reach the coaching server. Keep the Mac server running on the same Wi-Fi."
    case "offline-or-local-network-denied": return "Check Wi-Fi and allow Local Network access for GripIt Step 2 in iPhone Settings."
    case "timeout": return "AI took too long. Please retry."
    case "http-403": return "The server blocked this connection. Check the local hostname allowance."
    case "no-api-key": return "The coaching server has no API key configured."
    case "rejected", "unparsed": return "AI couldn't produce a usable answer. Please retry."
    default: return "AI coaching is unavailable. Please retry."
    }
  }
}
