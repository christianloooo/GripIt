import GripItScannerCore
import SwiftUI

struct ThrowEntryView: View {
  @ObservedObject var model: TrainingFlowModel
  @State private var feedback: FocusAssessment?
  @State private var showFeedback = false
  @State private var replacement: Bool?
  @FocusState private var editing: Bool

  var body: some View {
    ScrollViewReader { proxy in
      Form {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            TrainingStepLabel(step: 3)
            Text("Record your throw\non Rapsodo.").font(.title.bold())
            Text("Throw your \(model.pitch.shortTitle.lowercased()), then copy the readings below.")
              .font(.subheadline).foregroundStyle(.secondary)
            if model.usesSampleHand {
              Label("Sample hand", systemImage: "hand.raised").font(.caption).foregroundStyle(.mint)
            }
          }.padding(.vertical, 6)
        }
        .listRowBackground(Color.clear)

        if model.draft.source == .sample {
          Section {
            HStack {
              Label("Sample throws", systemImage: "flask").foregroundStyle(.mint)
              Spacer()
              Button("Use real throws") { requestReplacement(sample: false) }
                .font(.subheadline.weight(.semibold))
            }
          }
        }

        ForEach($model.draft.rows) { $row in
          Section {
            field("Velocity", value: $row.velocityMph, unit: "mph", key: "velocityMph", id: row.id)
            field(
              "Total spin", value: $row.totalSpinRpm, unit: "rpm", key: "totalSpinRpm", id: row.id)
            field(
              "Spin direction", value: $row.spinDirectionClock, unit: "12:30",
              key: "spinDirectionClock", id: row.id, clock: true)
            field(
              "Spin efficiency", value: $row.spinEfficiencyPercent, unit: "%",
              key: "spinEfficiencyPercent", id: row.id)
            field(
              "Gyro angle", value: $row.gyroDegree, unit: "°",
              key: "gyroDegree", id: row.id, signed: true)
            field(
              "Horizontal break", value: $row.horizontalBreakInches, unit: "in",
              key: "horizontalBreakInches", id: row.id, signed: true)
            field(
              "Vertical break", value: $row.verticalBreakInches, unit: "in",
              key: "verticalBreakInches", id: row.id, signed: true)
            field(
              "Release height", value: $row.releaseHeightFeet, unit: "ft", key: "releaseHeightFeet",
              id: row.id)
            DisclosureGroup("Optional score") {
              field(
                "Rapsodo score", value: $row.rapsodoScore, unit: "", key: "rapsodoScore", id: row.id
              )
            }
          } header: {
            HStack {
              Text("Throw \((model.draft.rows.firstIndex { $0.id == row.id } ?? 0) + 1)")
              Spacer()
              if model.draft.rows.count > 1 {
                Button("Remove", role: .destructive) { model.removeThrow(row.id) }
              }
            }
          }
          .id(row.id)
        }

        Section {
          Button {
            model.addThrow()
          } label: {
            Label("Add another throw", systemImage: "plus")
          }
          if model.draft.source != .sample {
            Button("Use sample throws") { requestReplacement(sample: true) }
              .foregroundStyle(.secondary)
          }
        } footer: {
          Text("One throw is enough. Three or more lets us check consistency.")
        }
      }
      .scrollContentBackground(.hidden)
      .scrollDismissesKeyboard(.interactively)
      .background(.black).preferredColorScheme(.dark).tint(.mint)
      .navigationTitle(model.pitch.shortTitle).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { editing = false }
        }
      }
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 8) {
          if let message = model.message { Text(message).font(.caption).foregroundStyle(.orange) }
          Button {
            editing = false
            if let result = model.assessment() {
              feedback = result
              showFeedback = true
            } else if let first = model.draft.rows.first(where: { model.errors[$0.id] != nil }) {
              withAnimation { proxy.scrollTo(first.id, anchor: .top) }
            }
          } label: {
            Label("See feedback", systemImage: "arrow.right")
              .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black)
          .accessibilityIdentifier("see-feedback")
        }.padding(.horizontal, 20).padding(.vertical, 12).background(.ultraThinMaterial)
      }
      .onChange(of: model.draft.rows.count) { _, _ in scrollToLatest(proxy) }
      .onAppear { scrollToLatest(proxy) }
      .confirmationDialog(
        "Replace these throw entries?",
        isPresented: Binding(
          get: { replacement != nil }, set: { if !$0 { replacement = nil } }
        ), titleVisibility: .visible
      ) {
        Button("Replace entries", role: .destructive) {
          if let replacement { model.replaceDraft(sample: replacement) }
          replacement = nil
        }
        Button("Cancel", role: .cancel) { replacement = nil }
      }
      .navigationDestination(isPresented: $showFeedback) {
        if let feedback { FocusAssessmentView(model: model, assessment: feedback) }
      }
    }
  }

  private func requestReplacement(sample: Bool) {
    if model.hasEntries { replacement = sample } else { model.replaceDraft(sample: sample) }
  }

  private func scrollToLatest(_ proxy: ScrollViewProxy) {
    if let last = model.draft.rows.last, last.velocityMph.isEmpty {
      withAnimation { proxy.scrollTo(last.id, anchor: .top) }
    }
  }

  private func field(
    _ title: String, value: Binding<String>, unit: String,
    key: String, id: String, clock: Bool = false, signed: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 12) {
        Text(title).font(.subheadline)
        Spacer(minLength: 8)
        TextField(clock ? "12:30" : "0", text: value)
          .multilineTextAlignment(.trailing)
          .keyboardType(clock || signed ? .numbersAndPunctuation : .decimalPad)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .focused($editing).frame(minWidth: 70, maxWidth: 110)
          .accessibilityLabel(title).accessibilityIdentifier("\(id)-\(key)")
        if !unit.isEmpty, !clock {
          Text(unit).font(.caption).foregroundStyle(.secondary).frame(
            width: 28, alignment: .trailing)
        }
      }
      if let error = model.errors[id]?[key] {
        Text(error).font(.caption).foregroundStyle(.orange)
      }
    }.padding(.vertical, 4)
  }
}
