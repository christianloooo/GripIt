import GripItScannerCore
import SwiftUI

struct GripViewerView: View {
  let profile: HandProfile
  /// Step 4 passes a numeric map under stable zone strings. nil is the normal studio.
  let zoneSeverity: GripSeverityMap?
  let onZoneSelect: (GripZoneID) -> Void
  @StateObject private var studio: GripStudioSession
  @State private var training: TrainingFlowModel?
  @State private var showThrows = false
  @State private var showHandModel = false
  @State private var showDetails = false
  @State private var plan: GripPlan?
  @State private var selectedZone: GripZoneID? = nil
  @State private var showPressure = true
  private var activeSeverity: GripSeverityMap? { zoneSeverity }
  @Environment(\.dismiss) private var dismiss
  @State private var pitch: PitchGrip = .fourSeam
  @State private var pose: GripPose?
  @State private var fit: StudioFit?
  @State private var error: String?
  @State private var loading = true
  @State private var contacts = false
  @State private var camera: GripCamera = .threeQuarter
  @State private var cameraReset = 0

  init(
    profile: HandProfile, initialPitch: PitchGrip = .fourSeam,
    initialCamera: GripCamera = .threeQuarter,
    zoneSeverity: GripSeverityMap? = nil, initialZone: GripZoneID? = nil,
    onZoneSelect: @escaping (GripZoneID) -> Void = { _ in }
  ) {
    self.profile = profile
    self.zoneSeverity = zoneSeverity
    self.onZoneSelect = onZoneSelect
    _studio = StateObject(wrappedValue: GripStudioSession(profile: profile))
    _pitch = State(initialValue: initialPitch)
    _camera = State(initialValue: initialCamera)
    _selectedZone = State(initialValue: initialZone)
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        TrainingStepLabel(step: 2)
        HStack(alignment: .firstTextBaseline) {
          Text("Find your grip.").font(.title2.bold())
          Spacer()
          Text(profile.capture.method.contains("sample") ? "SAMPLE HAND" : "YOUR HAND")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.mint)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.mint.opacity(0.09), in: Capsule())
        }
        Picker("Pitch type", selection: $pitch) {
          ForEach(PitchGrip.allCases) { p in Text(p.shortTitle).tag(p) }
        }.pickerStyle(.segmented)
        ZStack(alignment: .topLeading) {
          Canvas { context, size in
            var grid = Path()
            for x in stride(from: 0.0, through: size.width, by: 28) {
              grid.move(to: CGPoint(x: x, y: 0))
              grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0.0, through: size.height, by: 28) {
              grid.move(to: CGPoint(x: 0, y: y))
              grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.mint.opacity(0.055)), lineWidth: 0.5)
          }.allowsHitTesting(false)
          if let pose {
            GripSceneView(
              pose: pose, showContacts: false, camera: camera, reset: cameraReset,
              gripPlan: plan, render: fit?.render, zoneSeverity: activeSeverity,
              showPressure: zoneSeverity == nil && showPressure,
              showAnnotations: true, arcadeStyle: true, selectedZone: selectedZone,
              onZoneDismiss: { selectedZone = nil }, onZoneSelect: selectZone
            )
            .opacity(loading ? 0.15 : 1)
            .accessibilityLabel(
              "Interactive \(pose.pitch.title) grip. Drag to rotate and tap a numbered point.")
          }
          VStack(alignment: .leading, spacing: 5) {
            Text("GRIP EXPLORER").font(.system(size: 9, weight: .bold, design: .monospaced))
              .foregroundStyle(.mint)
            Text("Drag to rotate · Pinch to zoom").font(.system(size: 10)).foregroundStyle(
              .white.opacity(0.5))
          }.padding(14).allowsHitTesting(false)
          if loading {
            ProgressView("Building your grip…").tint(.mint)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
          if let error {
            ContentUnavailableView(
              "Grip unavailable", systemImage: "hand.raised", description: Text(error))
          }
        }
        .frame(maxWidth: .infinity).frame(minHeight: 360, maxHeight: .infinity)
        .background(Color(red: 0.035, green: 0.075, blue: 0.065))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.mint.opacity(0.13), lineWidth: 1))
        HStack(spacing: 12) {
          Menu {
            ForEach(GripCamera.allCases) { angle in
              Button(angle.title) {
                camera = angle
                cameraReset += 1
              }
            }
            Divider()
            if let plan {
              ForEach(plan.zones) { zone in Button(zone.title) { selectZone(zone.zoneId) } }
            }
          } label: {
            Label("Explore", systemImage: "viewfinder")
          }
          .accessibilityIdentifier("grip-view-menu")
          Button {
            camera = .threeQuarter
            cameraReset += 1
          } label: {
            Image(systemName: "arrow.counterclockwise")
          }.accessibilityLabel("Reset grip view")
          Spacer()
          Button {
            showPressure.toggle()
          } label: {
            Label("Effort", systemImage: showPressure ? "circle.lefthalf.filled" : "circle")
          }.accessibilityIdentifier("toggle-grip-effort")
        }.font(.caption.weight(.semibold)).buttonStyle(.bordered).tint(.mint)
        if showPressure && zoneSeverity == nil {
          HStack(spacing: 9) {
            Text("NO EFFORT")
            LinearGradient(
              colors: [.white, Color(red: 0.035, green: 0.29, blue: 0.21)], startPoint: .leading,
              endPoint: .trailing
            )
            .frame(height: 5).clipShape(Capsule())
            Text("MORE EFFORT")
          }.font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
      .background(Color(red: 0.025, green: 0.045, blue: 0.04))
      .preferredColorScheme(.dark)
      .navigationTitle("Grip studio").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button("Hand model", systemImage: "hand.raised") { showHandModel = true }
            Button("Model details", systemImage: "info.circle") { showDetails = true }
          } label: {
            Image(systemName: "ellipsis")
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button {
          if let fit {
            training = studio.training(for: fit)
            showThrows = true
          }
        } label: {
          HStack {
            Text("Record throws")
            Spacer()
            Image(systemName: "arrow.up.right")
          }
          .font(.headline).frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(
          Color(red: 0.025, green: 0.12, blue: 0.09)
        )
        .disabled(loading || fit == nil)
        .accessibilityIdentifier("record-throws")
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(red: 0.025, green: 0.045, blue: 0.04))
      }
      .navigationDestination(isPresented: $showThrows) {
        if let training { ThrowEntryView(model: training) }
      }
      .fullScreenCover(isPresented: $showHandModel) { HandModelReviewView(profile: profile) }
      .sheet(isPresented: $showDetails) {
        NavigationStack {
          ScrollView { modelDetails.padding(20) }.navigationTitle("Model details")
            .toolbar {
              ToolbarItem(placement: .confirmationAction) { Button("Done") { showDetails = false } }
            }
        }
        .preferredColorScheme(.dark)
      }
    }
    .task(id: pitch) {
      loading = true
      error = nil
      let selected = pitch
      do {
        let result = try await studio.fitted(selected)
        guard !Task.isCancelled else { return }
        fit = result
        pose = result.pose
        plan = result.plan
        if !result.plan.zones.contains(where: { $0.zoneId == selectedZone }) {
          selectedZone = nil
        }
        loading = false
      } catch {
        guard !Task.isCancelled else { return }
        fit = nil
        pose = nil
        plan = nil
        self.error = error.localizedDescription
        loading = false
      }
    }
  }
  private var modelDetails: some View {
    VStack(alignment: .leading, spacing: 16) {
      Toggle("Contact points", isOn: $contacts).tint(.mint)
      if zoneSeverity == nil {
        Toggle("Show grip pressure", isOn: $showPressure).tint(.mint)
      }
      if activeSeverity != nil {
        Text(
          zoneSeverity == nil
            ? "Darker green illustrates firmer grip pressure. This is not measured force."
            : "Uncolored zones have no assessment. Colors do not establish a pitch's cause."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 8) {
        Text(pitch.title).font(.headline)
        Text(pitch.orientation)
        Text(pitch.depth).foregroundStyle(.secondary)
      }
      if let pose, !loading {
        if pose.diagnostics.adjustedProportions {
          Text("Proportions adjusted to preserve natural anatomy.")
            .font(.caption).foregroundStyle(.secondary)
        }
        if pose.diagnostics.needsReview {
          Text(
            String(
              format: "Pad gap %.1f mm · Ball overlap %.1f mm",
              pose.diagnostics.maximumPadSurfaceGapMm, pose.diagnostics.maximumSkinPenetrationMm)
          )
          .font(.caption).foregroundStyle(.secondary)
          if pose.diagnostics.maximumContactGapMm > 6 {
            Text("Some fingers cannot reach their intended positions.")
              .font(.caption).foregroundStyle(.orange)
          }
          if let gap = pose.diagnostics.loopGapMm {
            Text(String(format: "Index–thumb spacing %.1f mm", gap))
              .font(.caption).foregroundStyle(.secondary)
          }
          if pose.diagnostics.seams.contains(where: \.needsReview) {
            Text("Seam alignment needs review.").font(.caption).foregroundStyle(.orange)
          }
        }
      }
      if let zone = plan?.zones.first(where: { $0.zoneId == selectedZone }), !loading {
        Text("\(zone.title): \(zone.reach.rawValue) reach")
          .font(.subheadline)
        Text(zone.reachEvidence).font(.caption).foregroundStyle(.secondary)
      }
      Text("Personalized model, not an exact skin scan. Pressure is illustrative.")
        .font(.caption).foregroundStyle(.secondary)
      DisclosureGroup("Model credits") {
        Text(
          "Hand: supplied Rigged Hands.blend, Hand.R. Source provenance is bundled with the app. Baseball: supplied Ball.glb, scaled to 73 mm."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }.padding(.top, 12)
  }

  private func selectZone(_ zone: GripZoneID) {
    guard plan?.zones.contains(where: { $0.zoneId == zone }) == true else { return }
    selectedZone = zone
    onZoneSelect(zone)
  }
  private func status(_ zone: GripZoneID) -> String {
    guard let value = activeSeverity?[zone], let band = GripSeverityBand.band(value) else {
      return "Unassessed"
    }
    return String(format: "%@ (%.2f)", band.label, value)
  }
  private func legend(_ label: String, _ color: Color) -> some View {
    HStack(spacing: 5) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text(label)
    }
  }

}

/// Uses actual skinned vertices, not a concept image, to review anatomy before a grip is fitted.
struct HandModelReviewView: View {
  let profile: HandProfile
  var initialCamera: GripCamera = .palm
  var initialFlexion = 0.0
  var initialWireframe = false
  @Environment(\.dismiss) private var dismiss
  @State private var pose: GripPose?
  @State private var error: String?
  @State private var camera: GripCamera = .palm
  @State private var reset = 0
  @State private var wireframe = false
  @State private var flexion = 0.0
  @State private var exportURL: URL?

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        Text(
          "\(profile.capture.method.contains("sample") ? "REFERENCE HAND" : "YOUR HAND") · \(profile.handedness.rawValue.uppercased())"
        )
        .font(.caption.weight(.semibold)).foregroundStyle(.mint)
        ZStack {
          if let pose {
            GripSceneView(
              pose: pose, showContacts: false, camera: camera, reset: reset,
              showBall: false, wireframe: wireframe)
          } else if let error {
            ContentUnavailableView(
              "Model unavailable", systemImage: "hand.raised", description: Text(error))
          } else {
            ProgressView("Building the hand surface…")
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 24))
          .clipShape(RoundedRectangle(cornerRadius: 24))
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
        HStack {
          Text("Finger bend").font(.subheadline)
          Slider(value: $flexion, in: 0...0.6, step: 0.1).tint(.mint)
            .accessibilityLabel("Review finger joint flexion")
        }
        Text("Drag to rotate · Pinch to zoom")
          .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        DisclosureGroup("Model details") {
          VStack(alignment: .leading, spacing: 12) {
            Toggle("Show mesh", isOn: $wireframe).tint(.mint)
            if let exportURL {
              ShareLink("Export 3D hand", item: exportURL).font(.subheadline)
            }
            Text("Personalized model, not an exact skin scan.")
              .font(.caption).foregroundStyle(.secondary)
          }.padding(.top, 8)
        }
      }.padding(20).background(.black).preferredColorScheme(.dark)
        .navigationTitle("Hand model").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
    }.onAppear {
      camera = initialCamera
      flexion = initialFlexion
      wireframe = initialWireframe
    }
    .task(id: flexion) {
      let profile = profile
      let amount = flexion
      do {
        let result = try await Task.detached {
          try GripPoseSolver.openHand(profile: profile, flexion: amount)
        }.value
        guard !Task.isCancelled else { return }
        pose = result
        if let exportURL { try? FileManager.default.removeItem(at: exportURL) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(
          "GripIt-Hand-\(UUID().uuidString).scn")
        let scene = GripSceneBuilder.scene(pose: result, showBall: false)
        exportURL =
          scene.write(to: file, options: nil, delegate: nil, progressHandler: nil) ? file : nil
        #if DEBUG
          if ProcessInfo.processInfo.arguments.contains("--save-hand-render"),
            let png = try GripSceneBuilder.reviewSheet(profile: profile).pngData()
          {
            try png.write(
              to: FileManager.default.temporaryDirectory.appendingPathComponent(
                "GripIt-Hand-Review.png"))
          }
        #endif
      } catch {
        guard !Task.isCancelled else { return }
        self.error = error.localizedDescription
      }
    }
    .onDisappear { if let exportURL { try? FileManager.default.removeItem(at: exportURL) } }
  }
}
