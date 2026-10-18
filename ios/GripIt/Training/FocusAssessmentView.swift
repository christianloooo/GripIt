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

  private let canvas = Color(red: 0.025, green: 0.045, blue: 0.04)

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        TrainingStepLabel(step: 4)
        HStack(alignment: .firstTextBaseline) {
          Text("Find your next adjustment.").font(.title2.bold())
          Spacer()
          Text(model.pitch.shortTitle.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.mint)
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
            context.stroke(grid, with: .color(.mint.opacity(0.055)), lineWidth: 0.5)
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
              .foregroundStyle(.mint)
            Text("Drag to rotate · Tap a point to explore")
              .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
          }.padding(14).allowsHitTesting(false)
        }
        .frame(height: 440)
        .background(Color(red: 0.035, green: 0.075, blue: 0.065))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.mint.opacity(0.13), lineWidth: 1))

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
        }.font(.caption.weight(.semibold)).buttonStyle(.bordered).tint(.mint)

        HStack(spacing: 14) {
          legend("Start here", .red)
          legend("Review", .yellow)
          legend("Checked", .green)
          legend("Not assessed", .gray)
        }.font(.system(size: 10)).frame(maxWidth: .infinity)

        VStack(alignment: .leading, spacing: 12) {
          Text("WHAT TO TRY NEXT")
            .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.mint)
          Text(assessment.nextAction.summary).font(.headline)
          if let change = assessment.changeToTry {
            Text(change).font(.subheadline)
          }
          if let expected = assessment.expectedMovement {
            Text(expected).font(.subheadline).foregroundStyle(.mint)
          }
          if assessment.changeToTry == nil && assessment.measuredSummary == nil {
            Text(assessment.nextAction.detail).font(.subheadline).foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))

        if let measured = assessment.measuredSummary {
          VStack(alignment: .leading, spacing: 8) {
            Text("YOUR READINGS")
              .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
            Text(measured).font(.subheadline).foregroundStyle(.secondary)
          }.padding(.horizontal, 2)
        }
        if !assessment.unreachableZones.isEmpty {
          Label("Some contacts need a better fit before changing your grip.", systemImage: "hand.raised")
            .font(.caption).foregroundStyle(.orange)
        }
        if let consistency = assessment.consistency {
          Text(String(format: "%d throws · Velocity spread %.1f mph · Spin spread %.0f rpm",
            consistency.throwCount, consistency.velocitySpreadMph, consistency.totalSpinSpreadRpm))
            .font(.caption).foregroundStyle(.secondary)
        }
        Text("Colors show grip checks to try, not measured finger pressure.")
          .font(.caption2).foregroundStyle(.secondary)
      }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
    }
    .background(canvas).preferredColorScheme(.dark).tint(.mint)
    .navigationTitle("Feedback").navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      Button { model.addThrow(); dismiss() } label: {
        HStack { Text("Record another throw"); Spacer(); Image(systemName: "arrow.up.right") }
          .font(.headline).frame(maxWidth: .infinity, minHeight: 40)
      }
      .buttonStyle(.borderedProminent).tint(.mint)
      .foregroundStyle(Color(red: 0.025, green: 0.12, blue: 0.09))
      .padding(.horizontal, 16).padding(.vertical, 10).background(canvas)
    }
    .onAppear {
      selectedZone = selectedZone ?? assessment.nextAction.zoneId
    }
  }

  private func legend(_ text: String, _ color: Color) -> some View {
    HStack(spacing: 4) { Circle().fill(color).frame(width: 6, height: 6); Text(text) }
  }
}
