import GripItScannerCore
import SwiftUI

struct FocusAssessmentView: View {
  @ObservedObject var model: TrainingFlowModel
  let assessment: FocusAssessment
  @Environment(\.dismiss) private var dismiss
  @State private var selectedZone: GripZoneID?
  @State private var camera: GripCamera = .threeQuarter
  @State private var reset = 0
  @State private var showHeatmap = true
  @State private var showDetails = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        TrainingStepLabel(step: 4)
        HStack(alignment: .firstTextBaseline) {
          Text("Find your next adjustment.").font(.title2.bold())
          Spacer()
          Text(model.pitch.shortTitle.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(GripItTheme.accent)
        }

        // Reuse the solved pose, plan and surface data from Step 2.
        ZStack(alignment: .topLeading) {
          Canvas { context, size in
            var grid = Path()
            for x in stride(from: 0.0, through: size.width, by: 28) {
              grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0.0, through: size.height, by: 28) {
              grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(GripItTheme.accent.opacity(0.055)), lineWidth: 0.5)
          }.allowsHitTesting(false)
          GripSceneView(
            pose: model.fit.pose, showContacts: false, camera: camera, reset: reset,
            gripPlan: model.fit.plan, render: model.fit.render,
            zoneSeverity: showHeatmap ? assessment.severityMap : nil,
            showAnnotations: true, arcadeStyle: true, focusAssessment: assessment,
            selectedZone: selectedZone, onZoneDismiss: { selectedZone = nil },
            onZoneSelect: { selectedZone = $0 }
          )
          .accessibilityLabel("Interactive \(model.pitch.title) hand with throw feedback")
          VStack(alignment: .leading, spacing: 5) {
            Text("THROW REVIEW").font(.system(size: 9, weight: .bold, design: .monospaced))
              .foregroundStyle(GripItTheme.accent)
            Text("Drag to rotate · Tap a point to explore")
              .font(.system(size: 10)).foregroundStyle(GripItTheme.secondary)
          }.padding(14).allowsHitTesting(false)
        }
        .frame(height: 440)
        .gripitGlassSurface(radius: 24)
        .clipShape(RoundedRectangle(cornerRadius: 24))

        HStack {
          Menu {
            ForEach(GripCamera.allCases) { angle in
              Button(angle.title) { camera = angle; reset += 1 }
            }
            Divider()
            ForEach(model.fit.plan.zones) { zone in
              Button(zone.title) { selectedZone = zone.zoneId }
            }
          } label: { Label("Explore", systemImage: "viewfinder") }
          Button { camera = .threeQuarter; reset += 1 } label: {
            Image(systemName: "arrow.counterclockwise")
          }.accessibilityLabel("Reset feedback view")
          Spacer()
          Button { showHeatmap.toggle() } label: {
            Label("Heatmap", systemImage: showHeatmap ? "circle.lefthalf.filled" : "circle")
          }.accessibilityIdentifier("toggle-feedback-heatmap")
        }.font(.caption.weight(.semibold)).buttonStyle(GripItGlassButtonStyle()).tint(GripItTheme.accent)

        HStack(spacing: 14) {
          legend("Start here", .red)
          legend("Review", .yellow)
          legend("Checked", .green)
          legend("Not assessed", .gray)
        }.font(.system(size: 10)).frame(maxWidth: .infinity)

        VStack(alignment: .leading, spacing: 12) {
          Text("TRY THIS FIRST")
            .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(GripItTheme.accent)
          Text(assessment.primaryAction).font(.headline)
          if !assessment.secondaryActions.isEmpty {
            Text("THEN CHECK")
              .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.yellow)
            ForEach(assessment.secondaryActions) { finding in
              Button { selectedZone = finding.zoneId } label: {
                HStack(alignment: .top, spacing: 10) {
                  Circle().fill(.yellow).frame(width: 8, height: 8).padding(.top, 5)
                  Text(finding.action ?? "").font(.subheadline).multilineTextAlignment(.leading)
                  Spacer(minLength: 0)
                  Image(systemName: "chevron.right").font(.caption)
                }.foregroundStyle(.white)
              }.buttonStyle(GripItGlassButtonStyle(kind: .quiet))
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .gripitGlassSurface(radius: 20)

      }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
    }
    .gripitScreen().tint(GripItTheme.accent)
    .navigationTitle("Feedback").navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      HStack(spacing: 12) {
      Button { model.addThrow(); dismiss() } label: {
        HStack { Text("Record another throw"); Spacer(); Image(systemName: "arrow.up.right") }
          .font(.headline).frame(maxWidth: .infinity, minHeight: 40)
      }
      .buttonStyle(GripItGlassButtonStyle(kind: .primary)).tint(GripItTheme.accent)
      .foregroundStyle(GripItTheme.text)
      Button { showDetails = true } label: {
        VStack(spacing: 4) {
          Image(systemName: "text.alignleft").font(.title3)
          Text("Details").font(.caption)
        }.frame(width: 54, height: 52)
      }.buttonStyle(GripItGlassButtonStyle(kind: .quiet)).foregroundStyle(GripItTheme.accent)
        .accessibilityIdentifier("feedback-details")
      }
      .padding(.horizontal, 16).padding(.vertical, 10).background(GripItBackdrop())
    }
    .sheet(isPresented: $showDetails) { feedbackDetails }
    .onAppear {
      selectedZone = selectedZone ?? assessment.nextAction.zoneId
    }
  }

  private func legend(_ text: String, _ color: Color) -> some View {
    HStack(spacing: 4) { Circle().fill(color).frame(width: 6, height: 6); Text(text) }
  }

  private var feedbackDetails: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          detail("Why start here?", assessment.nextAction.summary)
          if let measured = assessment.measuredSummary { detail("Your readings", measured) }
          if let change = assessment.changeToTry { detail("Full grip instruction", change) }
          if let expected = assessment.expectedMovement { detail("What to look for", expected) }
          ForEach(assessment.zones) { finding in
            VStack(alignment: .leading, spacing: 8) {
              Text("\(finding.zoneId.title) · \(finding.severity.title)").font(.headline)
              Text(assessment.action(for: finding.zoneId)).font(.subheadline)
              Text(finding.reason).font(.subheadline).foregroundStyle(GripItTheme.secondary)
              if let zone = model.fit.plan.zones.first(where: { $0.zoneId == finding.zoneId }) {
                Text(zone.instruction).font(.caption).foregroundStyle(GripItTheme.secondary)
              }
            }
          }
          if let consistency = assessment.consistency {
            detail("Across your throws", String(format:
              "%d throws · Velocity spread %.1f mph · Spin spread %.0f rpm",
              consistency.throwCount, consistency.velocitySpreadMph, consistency.totalSpinSpreadRpm))
          }
          detail("About the colors",
            "Red is the first adjustment to try; yellow shows another check to review next; green is a check with no change suggested. Uncolored areas have no assessment. Colors are not measured finger pressure.")
        }.padding(20)
      }.gripitScreen().navigationTitle("Throw details").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
          Button("Done") { showDetails = false }
        } }
    }.preferredColorScheme(.dark).tint(GripItTheme.text)
  }

  private func detail(_ title: String, _ body: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.headline)
      Text(body).font(.subheadline).foregroundStyle(GripItTheme.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
