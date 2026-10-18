import GripItScannerCore
import SwiftUI

struct GripViewerView: View {
  let profile: HandProfile
  /// Step 4 passes a numeric map under stable zone strings. nil is the normal studio.
  let zoneSeverity: GripSeverityMap?
  let onZoneSelect: (GripZoneID) -> Void
  @State private var showHandModel = false
  @State private var plan: GripPlan?
  @State private var selectedZone: GripZoneID = .indexPad
  @State private var sampleHeatmap = false
  private var activeSeverity: GripSeverityMap? { zoneSeverity ?? (sampleHeatmap ? .sample : nil) }
  @Environment(\.dismiss) private var dismiss
  @State private var pitch: PitchGrip = .fourSeam
  @State private var pose: GripPose?
  @State private var error: String?
  @State private var loading = true
  @State private var contacts = false
  @State private var camera: GripCamera = .threeQuarter
  @State private var cameraReset = 0

  init(
    profile: HandProfile, initialPitch: PitchGrip = .fourSeam,
    initialCamera: GripCamera = .threeQuarter,
    zoneSeverity: GripSeverityMap? = nil, previewHeatmap: Bool = false,
    onZoneSelect: @escaping (GripZoneID) -> Void = { _ in }
  ) {
    self.profile = profile
    self.zoneSeverity = zoneSeverity
    self.onZoneSelect = onZoneSelect
    _sampleHeatmap = State(initialValue: previewHeatmap)
    _pitch = State(initialValue: initialPitch)
    _camera = State(initialValue: initialCamera)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          VStack(alignment: .leading, spacing: 6) {
            Text(
              "\(profile.capture.method.contains("sample") ? "SAMPLE HAND" : "YOUR HAND") · \(profile.handedness.rawValue.uppercased())"
            )
            .font(.caption.weight(.semibold)).foregroundStyle(.mint)
            Text("Find the grip.").font(.largeTitle.bold())
            Text(
              profile.capture.method.contains("sample")
                ? "Sample proportions. Scan your hand for a personal fit."
                : "Shaped from your measured hand profile."
            )
            .foregroundStyle(.secondary)
          }
          Picker("Pitch type", selection: $pitch) {
            ForEach(PitchGrip.allCases) { p in Text(p.shortTitle).tag(p) }
          }.pickerStyle(.segmented)
          ZStack(alignment: .topLeading) {
            if let pose {
              GripSceneView(
                pose: pose, showContacts: contacts, camera: camera, reset: cameraReset,
                gripPlan: plan, zoneSeverity: activeSeverity, selectedZone: selectedZone,
                onZoneSelect: selectZone
              )
              .opacity(loading ? 0.25 : 1)
              .accessibilityLabel(
                "3D \(pose.pitch.title) grip for your \(profile.handedness.rawValue) hand")
            }
            if loading {
              ProgressView("Fitting your hand…").tint(.mint).frame(
                maxWidth: .infinity, maxHeight: .infinity)
            }
            if activeSeverity != nil, !loading, pose != nil {
              Label(
                zoneSeverity == nil ? "Sample heat map" : "Diagnostic heat map",
                systemImage: "circle.hexagongrid.fill"
              )
              .font(.caption.weight(.semibold)).padding(10)
              .background(.black.opacity(0.7), in: Capsule()).padding(14)
              .allowsHitTesting(false)
            }
            if let error {
              ContentUnavailableView(
                "Grip unavailable for these proportions", systemImage: "hand.raised",
                description: Text(error))
            }
          }
          .frame(maxWidth: .infinity).frame(height: 390)
          .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 24))
          .clipShape(RoundedRectangle(cornerRadius: 24))
          Text("Drag to rotate · Pinch to zoom · Two fingers to pan")
            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
          HStack {
            ForEach(GripCamera.allCases) { c in
              Button(c.title) {
                camera = c
                cameraReset += 1
              }
              .buttonStyle(.bordered).tint(camera == c ? .mint : .gray)
            }
          }.frame(maxWidth: .infinity)
          if zoneSeverity == nil {
            Toggle("Preview diagnostic heat map", isOn: $sampleHeatmap).tint(.mint)
          }
          if activeSeverity != nil {
            VStack(alignment: .leading, spacing: 8) {
              Text(zoneSeverity == nil ? "SAMPLE DIAGNOSTICS" : "DIAGNOSTIC HEAT MAP")
                .font(.caption.bold()).foregroundStyle(.mint)
              HStack(spacing: 16) {
                legend("Low < 0.2", .green)
                legend("Review < 0.5", .yellow)
                legend("High ≥ 0.5", .red)
              }.font(.caption)
              Text(
                zoneSeverity == nil
                  ? "Illustrative values only. These colors are not results from your throw. Missing values stay unassessed."
                  : "Step 4 severity results. Missing values stay unassessed. A highlighted zone does not establish what caused a pitch outcome."
              )
              .font(.caption).foregroundStyle(.secondary)
            }
          }
          Toggle("Show contact points", isOn: $contacts).tint(.mint)
          if let plan, !loading {
            VStack(alignment: .leading, spacing: 12) {
              Text("Inspect a zone").font(.headline)
              Text("Tap the hand or choose below. Rotate to see an obscured contact.")
                .font(.caption).foregroundStyle(.secondary)
              LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(plan.zones) { zone in
                  Button {
                    selectZone(zone.zoneId)
                  } label: {
                    HStack {
                      if selectedZone == zone.zoneId { Image(systemName: "checkmark.circle.fill") }
                      Text(zone.title)
                    }.font(.subheadline).frame(maxWidth: .infinity, minHeight: 36)
                  }
                  .buttonStyle(.bordered).tint(selectedZone == zone.zoneId ? .white : .gray)
                  .accessibilityIdentifier(zone.zoneId.rawValue)
                  .accessibilityLabel(
                    "\(zone.title), \(status(zone.zoneId)), reach \(zone.reach.rawValue)"
                  )
                  .accessibilityAddTraits(selectedZone == zone.zoneId ? .isSelected : [])
                }
              }
              if let zone = plan.zones.first(where: { $0.zoneId == selectedZone }) {
                VStack(alignment: .leading, spacing: 8) {
                  HStack {
                    Image(systemName: "scope")
                    Text(zone.title).font(.headline)
                    Spacer()
                    Text(zone.zoneId.rawValue).font(.caption.monospaced()).foregroundStyle(
                      .secondary)
                  }
                  Text(zone.instruction)
                  Text(
                    "Intended pressure: \(zone.pressure?.rawValue ?? "unspecified") · Role: \(zone.role?.rawValue ?? "unspecified")"
                  )
                  .font(.subheadline).foregroundStyle(.secondary)
                  Text(
                    "Reach: \(zone.reach.rawValue)"
                      + (zone.shortfallMm.map { String(format: " · %.1f mm geometric error", $0) }
                        ?? " · no geometric target")
                  )
                  .font(.subheadline).foregroundStyle(
                    zone.reach == .comfortable ? Color.secondary : .orange)
                  if let placement = zone.placement {
                    Text(
                      "\(placement.surface.rawValue.capitalized) · \(placement.region.rawValue) · Seam: \(placement.seam.rawValue)"
                        + (placement.seamOffsetMm.map { String(format: " (%.0f mm)", $0) } ?? "")
                    )
                    .font(.caption)
                    if !placement.opposes.isEmpty {
                      Text(
                        "Opposes: " + placement.opposes.map(\.title).joined(separator: " + ")
                          + (placement.opposes.count > 1 ? " midpoint" : "")
                      )
                      .font(.caption)
                    }
                  }
                  if activeSeverity != nil {
                    Text("Diagnostic severity: \(status(zone.zoneId))").font(.subheadline.bold())
                  }
                  if zone.extrapolated {
                    Text("Wrist guidance is extrapolated, not measured or coach validated.").font(
                      .caption
                    ).foregroundStyle(.orange)
                  }
                  DisclosureGroup("How reach is estimated") {
                    Text(zone.reachEvidence).font(.caption).foregroundStyle(.secondary)
                  }
                }.padding(16).background(
                  Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
              }
            }
          }
          if let pose, !loading {
            if pose.diagnostics.needsReview {
              Label(
                "Approximate fit — inspect before copying", systemImage: "exclamationmark.triangle"
              )
              .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
              Text(
                String(
                  format: "Pad-to-ball gap %.1f mm · Ball overlap %.1f mm",
                  pose.diagnostics.maximumPadSurfaceGapMm, pose.diagnostics.maximumSkinPenetrationMm
                )
              )
              .font(.caption).foregroundStyle(.secondary)
              if pose.diagnostics.maximumContactGapMm > 6 {
                Text("Some fingers cannot reach their intended positions.").font(.caption)
                  .foregroundStyle(.orange)
              }
              if let gap = pose.diagnostics.loopGapMm, gap > 5 {
                Text(String(format: "Index–thumb loop gap %.1f mm", gap)).font(.caption)
                  .foregroundStyle(.orange)
              }
              if pose.diagnostics.seams.contains(where: \.needsReview) {
                Text("Seam alignment needs review.").font(.caption).foregroundStyle(.orange)
              }
            }
          }
          VStack(alignment: .leading, spacing: 10) {
            Text(pitch.title).font(.title2.bold())
            Text(pitch.orientation)
            Text(pitch.depth).foregroundStyle(.secondary)
          }
          Text(
            "A 73 mm baseball and your measured finger lengths drive the fit. Skin, nails, palm thickness, and finger thickness are modeled; this is not a reconstruction of your exact skin. Intended pressure is first-pass guidance for coach review, not measured pressure. A grip illustration does not predict pitch movement."
          )
          .font(.caption).foregroundStyle(.secondary)
          DisclosureGroup("Model credits") {
            Text(
              "Hand: Immersive Web WebXR Input Profiles, MIT. Baseball: project-supplied Ball.glb, clean variant with its PBR textures. Hand surface subdivided and proportioned; ball normalized to 73 mm. Licenses are bundled with the app."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        }.padding(20)
      }
      .background(Color.black).preferredColorScheme(.dark)
      .navigationTitle("Grip studio").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Hand model") { showHandModel = true } }
        ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
      }
      .fullScreenCover(isPresented: $showHandModel) { HandModelReviewView(profile: profile) }
    }
    .task(id: pitch) {
      loading = true
      error = nil
      let selected = pitch
      let profile = profile
      let task = Task.detached(priority: .userInitiated) {
        let pose = try GripPoseSolver.solve(profile: profile, pitch: selected)
        return (pose, GripPlan(pose: pose))
      }
      do {
        let result = try await withTaskCancellationHandler(
          operation: { try await task.value }, onCancel: { task.cancel() })
        guard !Task.isCancelled else { return }
        pose = result.0
        plan = result.1
        if !result.1.zones.contains(where: { $0.zoneId == selectedZone }) {
          selectedZone = .indexPad
        }
        loading = false
      } catch {
        guard !Task.isCancelled else { return }
        pose = nil
        plan = nil
        self.error = error.localizedDescription
        loading = false
      }
    }
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
        Text("Hand anatomy").font(.largeTitle.bold())
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
          }
        }.frame(maxWidth: .infinity)
        HStack {
          Text("Finger bend").font(.subheadline)
          Slider(value: $flexion, in: 0...0.6, step: 0.1).tint(.mint)
            .accessibilityLabel("Review finger joint flexion")
        }
        Toggle("Inspect mesh topology", isOn: $wireframe).tint(.mint)
        if let exportURL {
          ShareLink("Export 3D hand (.scn)", item: exportURL).font(.subheadline)
        }
        Text(
          "Drag to rotate · Pinch to zoom. This is the same personalized mesh used in the grip viewer. Thickness and skin details are modeled where the scan provides no measurement."
        )
        .font(.caption).foregroundStyle(.secondary)
      }.padding(20).background(.black).preferredColorScheme(.dark)
        .navigationTitle("Model review").navigationBarTitleDisplayMode(.inline)
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
