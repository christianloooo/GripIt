import GripItScannerCore
import SceneKit
import SwiftUI
import simd

public enum GripCamera: String, CaseIterable, Identifiable {
  case threeQuarter, fingers, palm, thumbSide, back
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .threeQuarter: "Reset"
    case .fingers: "Fingers"
    case .palm: "Palm"
    case .thumbSide: "Thumb"
    case .back: "Back"
    }
  }
}
struct GripSceneView: UIViewRepresentable {
  let pose: GripPose
  let showContacts: Bool
  let camera: GripCamera
  let reset: Int
  var showBall = true
  var wireframe = false
  var gripPlan: GripPlan? = nil
  /// Prebuilt zone surface and shading weights for this pose. Supplying it keeps
  /// the ~190 ms derivation off the main thread when the pitch changes.
  var render: GripRenderState? = nil
  var zoneSeverity: GripSeverityMap? = nil
  var showPressure = false
  var showAnnotations = false
  var arcadeStyle = false
  var focusAssessment: FocusAssessment? = nil
  var selectedZone: GripZoneID? = nil
  var onZoneDismiss: () -> Void = {}
  var onZoneSelect: (GripZoneID) -> Void = { _ in }
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeUIView(context: Context) -> SCNView {
    let view = SCNView()
    view.backgroundColor = arcadeStyle ? .clear : UIColor(GripItTheme.surface)
    view.antialiasingMode = .multisampling4X
    view.allowsCameraControl = true
    view.defaultCameraController.inertiaEnabled = true
    view.defaultCameraController.interactionMode = .orbitTurntable
    context.coordinator.onZoneSelect = onZoneSelect
    context.coordinator.onZoneDismiss = onZoneDismiss
    context.coordinator.update(
      view, pose: pose, contacts: showContacts, camera: camera, reset: reset,
      plan: gripPlan ?? render?.plan ?? GripPlan(pose: pose), render: render,
      severity: zoneSeverity, selected: selectedZone,
      showBall: showBall, wireframe: wireframe, pressure: showPressure,
      annotations: showAnnotations, arcade: arcadeStyle, assessment: focusAssessment)
    let tap = UITapGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.selectZone(_:)))
    tap.cancelsTouchesInView = false
    view.addGestureRecognizer(tap)
    context.coordinator.tap = tap
    for pinch in view.gestureRecognizers?.compactMap({ $0 as? UIPinchGestureRecognizer }) ?? [] {
      pinch.addTarget(context.coordinator, action: #selector(Coordinator.limitZoom(_:)))
    }
    return view
  }
  func updateUIView(_ view: SCNView, context: Context) {
    context.coordinator.onZoneSelect = onZoneSelect
    context.coordinator.onZoneDismiss = onZoneDismiss
    context.coordinator.update(
      view, pose: pose, contacts: showContacts, camera: camera, reset: reset,
      plan: gripPlan ?? render?.plan ?? GripPlan(pose: pose), render: render,
      severity: zoneSeverity, selected: selectedZone,
      showBall: showBall, wireframe: wireframe, pressure: showPressure,
      annotations: showAnnotations, arcade: arcadeStyle, assessment: focusAssessment)
  }
  static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
    if let tap = coordinator.tap { view.removeGestureRecognizer(tap) }
    for pinch in view.gestureRecognizers?.compactMap({ $0 as? UIPinchGestureRecognizer }) ?? [] {
      pinch.removeTarget(coordinator, action: #selector(Coordinator.limitZoom(_:)))
    }
    coordinator.displayLink?.invalidate()
    coordinator.displayLink = nil
    coordinator.projectionDriver = nil
    coordinator.graphOverlay?.removeFromSuperview()
    coordinator.graphOverlay = nil
    coordinator.annotationView = nil
    view.scene = nil
    coordinator.content = nil
    coordinator.cameraNode = nil
    coordinator.markerNode = nil
    coordinator.surface = nil
    coordinator.hand = nil
    coordinator.baseGeometry = nil
    coordinator.indices = []
    coordinator.vertices = []
    coordinator.tap = nil
    view.pointOfView = nil
    view.allowsCameraControl = false
    coordinator.onZoneSelect = { _ in }
  }
  @MainActor final class Coordinator: NSObject {
    weak var annotationView: SCNView?
    var graphOverlay: GripGraphOverlay?
    var displayLink: CADisplayLink?
    var projectionDriver: GripProjectionDriver?
    var annotationCandidates: [GripZoneID: [SCNVector3]] = [:]
    var showingArcade = false
    var showingAnnotations = false
    var onZoneDismiss: () -> Void = {}
    var poseID: UUID?
    var showingBall = true
    var showingWireframe = false
    var tap: UITapGestureRecognizer?
    var surface: GripZoneSurface?
    var indices: [UInt32] = []
    var vertices: [SIMD3<Double>] = []
    var hand: SCNNode?
    var baseGeometry: SCNGeometry?
    var severity: GripSeverityMap?
    var showingPressure = false
    var pressureWeights: [Double] = []
    var planData: Data?
    var selected: GripZoneID?
    var onZoneSelect: (GripZoneID) -> Void = { _ in }

    @objc func limitZoom(_ recognizer: UIPinchGestureRecognizer) {
      guard let view = recognizer.view as? SCNView else { return }
      clampZoom(view)
    }
    func clampZoom(_ view: SCNView) {
      guard let camera = view.pointOfView else { return }
      let target = view.defaultCameraController.target
      let center = SIMD3<Float>(target.x, target.y, target.z)
      let offset = camera.simdWorldPosition - center
      let distance = simd_length(offset)
      guard distance.isFinite, distance > 0.001 else { return }
      let clamped = min(650, max(150, distance))
      if abs(clamped - distance) > 0.01 {
        camera.simdWorldPosition = center + offset * (clamped / distance)
      }
    }
    @objc func selectZone(_ recognizer: UITapGestureRecognizer) {
      guard let view = recognizer.view as? SCNView else { return }
      if graphOverlay?.point(inside: recognizer.location(in: view), with: nil) == true { return }
      guard
        let hit = view.hitTest(
          recognizer.location(in: view),
          options: [.searchMode: SCNHitTestSearchMode.closest.rawValue, .categoryBitMask: 1]
        ).first,
        hit.node.name == "measured-hand", let surface
      else { return }
      // Barycentric coordinates in the hand's canonical local coordinates (left mirroring remains on its parent).
      let face = hit.faceIndex
      guard face >= 0, face * 3 + 2 < indices.count else { return }
      let a = vertices[Int(indices[face * 3])]
      let b = vertices[Int(indices[face * 3 + 1])]
      let c = vertices[Int(indices[face * 3 + 2])]
      let p = SIMD3(
        Double(hit.localCoordinates.x), Double(hit.localCoordinates.y),
        Double(hit.localCoordinates.z))
      let v0 = b - a
      let v1 = c - a
      let v2 = p - a
      let d00 = simd_dot(v0, v0)
      let d01 = simd_dot(v0, v1)
      let d11 = simd_dot(v1, v1)
      let denom = d00 * d11 - d01 * d01
      guard abs(denom) > 1e-12 else { return }
      let v = (d11 * simd_dot(v2, v0) - d01 * simd_dot(v2, v1)) / denom
      let w = (d00 * simd_dot(v2, v1) - d01 * simd_dot(v2, v0)) / denom
      if let zone = surface.zone(face: face, barycentric: SIMD3(1 - v - w, v, w), indices: indices)
      {
        onZoneSelect(zone)
      }
    }
    var reset = -1
    var content: SCNNode?
    var cameraNode: SCNNode?
    var markerNode: SCNNode?
    func update(
      _ view: SCNView, pose: GripPose, contacts: Bool, camera: GripCamera, reset: Int,
      plan: GripPlan, render: GripRenderState? = nil, severity: GripSeverityMap?,
      selected: GripZoneID?,
      showBall: Bool = true, wireframe: Bool = false, pressure: Bool = false,
      annotations: Bool = false, arcade: Bool = false, assessment: FocusAssessment? = nil
    ) {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      let planData = try? encoder.encode(plan)
      let planChanged = self.planData != planData
      let changed =
        poseID != pose.id || content == nil || showingBall != showBall || showingArcade != arcade
      if changed {
        let scene = GripSceneBuilder.scene(pose: pose, showBall: showBall)
        if arcade { GripSceneBuilder.applyArcadeStyle(scene, pose: pose) }
        view.backgroundColor = arcade ? .clear : UIColor(GripItTheme.surface)
        showingArcade = arcade
        view.scene = scene
        content = scene.rootNode.childNode(withName: "hand-and-ball", recursively: false)
        markerNode = scene.rootNode.childNode(withName: "contact-points", recursively: true)
        cameraNode = scene.rootNode.childNode(withName: "camera", recursively: false)
        view.pointOfView = cameraNode
        view.defaultCameraController.target = SCNVector3(0, annotations ? 32 : 60, annotations ? 30 : 15)
        poseID = pose.id
        showingBall = showBall
        hand = scene.rootNode.childNode(withName: "measured-hand", recursively: true)
        baseGeometry = hand?.geometry
        indices = pose.indices
        vertices = pose.vertices
        self.reset = -1
      }
      if changed || planChanged {
        if let render, let planData, render.pose.id == pose.id,
          (try? encoder.encode(render.plan)) == planData
        {
          surface = render.surface
          pressureWeights = render.pressureWeights
        } else if let asset = try? GripHandAsset.load() {
          surface = GripZoneSurface(pose: pose, gripPlan: plan, hand: asset)
          pressureWeights = GripPoseSolver.pressureShadingWeights(
            hand: asset, pose: pose, plan: plan)
        }
        annotationCandidates = Dictionary(
          uniqueKeysWithValues: plan.zones.map { zone in
            let target: SIMD3<Double>
            if let finger = pose.fingers.first(where: { $0.finger == zone.zoneId.finger }) {
              target =
                zone.placement?.surface == .side || zone.placement?.surface == .curl
                ? (finger.points[1] + finger.points[2]) / 2
                : finger.points[2] * 0.4 + finger.points[3] * 0.6
            } else {
              target = zone.zoneId == .wrist ? SIMD3(0, -2, 0) : SIMD3(0, 48, 12)
            }
            let ids = pose.vertices.indices.filter { surface?.picking[$0] == zone.zoneId }
              .sorted {
                simd_distance_squared(pose.vertices[$0], target)
                  < simd_distance_squared(pose.vertices[$1], target)
              }.prefix(100)
            return (zone.zoneId, ids.map { GripSceneBuilder.vector(pose.vertices[$0]) })
          })
        self.planData = planData
      }
      if changed || planChanged || self.severity != severity || self.selected != selected
        || showingPressure != pressure
      {
        if let surface, let baseGeometry {
          hand?.geometry = GripSceneBuilder.colored(
            baseGeometry, surface: surface, severity: severity,
            pressure: severity == nil && pressure ? pressureWeights : nil)
          hand?.childNode(withName: "zone-selection", recursively: false)?.removeFromParentNode()
          if let selected {
            hand?.addChildNode(
              GripSceneBuilder.outline(
                vertices: vertices, indices: indices, surface: surface, zone: selected))
          }
        }
        showingPressure = pressure
        self.severity = severity
        self.selected = selected
      }
      if changed || showingWireframe != wireframe {
        hand?.geometry?.firstMaterial?.fillMode = wireframe ? .lines : .fill
        showingWireframe = wireframe
      }
      markerNode?.isHidden = !contacts || !showBall
      if annotations {
        if graphOverlay == nil {
          let overlay = GripGraphOverlay(frame: view.bounds)
          overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
          view.addSubview(overlay)
          graphOverlay = overlay
          annotationView = view
          let driver = GripProjectionDriver()
          driver.coordinator = self
          projectionDriver = driver
          let link = CADisplayLink(target: driver, selector: #selector(GripProjectionDriver.tick))
          link.preferredFramesPerSecond = 30
          link.add(to: .main, forMode: .common)
          displayLink = link
        }
        graphOverlay?.onSelect = { [weak self] zone in self?.onZoneSelect(zone) }
        graphOverlay?.onClose = { [weak self] in self?.onZoneDismiss() }
        graphOverlay?.configure(plan: plan, selected: selected, assessment: assessment)
        graphOverlay?.isHidden = false
        displayLink?.isPaused = false
      } else {
        graphOverlay?.isHidden = true
        displayLink?.isPaused = true
      }
      if showingAnnotations != annotations { self.reset = -1 }
      showingAnnotations = annotations
      if self.reset != reset {
        let sign: Float = pose.handedness == .left ? -1 : 1
        switch camera {
        case .threeQuarter: cameraNode?.position = SCNVector3(-170 * sign, 155, 260)
        case .fingers: cameraNode?.position = SCNVector3(-100 * sign, 270, 160)
        case .palm: cameraNode?.position = SCNVector3(0, 75, 300)
        case .thumbSide: cameraNode?.position = SCNVector3(290 * sign, 90, 80)
        case .back: cameraNode?.position = SCNVector3(0, 85, -290)
        }
        if showBall && annotations, let cameraNode {
          cameraNode.simdPosition *= 1.15
        }
        if !showBall {
          switch camera {
          case .threeQuarter: cameraNode?.position = SCNVector3(-170 * sign, 120, 340)
          case .fingers: cameraNode?.position = SCNVector3(-170 * sign, 120, 340)
          case .palm: cameraNode?.position = SCNVector3(0, 85, 360)
          case .thumbSide: cameraNode?.position = SCNVector3(350 * sign, 100, 100)
          case .back: cameraNode?.position = SCNVector3(0, 85, -360)
          }
          view.defaultCameraController.target = SCNVector3(0, 80, 0)
        }
        cameraNode?.look(
          at: showBall ? SCNVector3(0, annotations ? 32 : 60, annotations ? 30 : 15) : SCNVector3(0, 80, 0))
        view.pointOfView = cameraNode
        self.reset = reset
      }
      if annotations { projectAnnotations() }
    }
    func projectAnnotations() {
      guard let view = annotationView, let hand, let camera = view.pointOfView,
        let overlay = graphOverlay, !overlay.isHidden
      else { return }
      let eye = SIMD3<Float>(camera.presentation.worldPosition)
      var points: [GripZoneID: CGPoint] = [:]
      for (zone, candidates) in annotationCandidates {
        let world = candidates.map { hand.convertPosition($0, to: nil) }
        guard
          let anchor = world.min(by: {
            simd_distance_squared(SIMD3<Float>($0), eye)
              < simd_distance_squared(SIMD3<Float>($1), eye)
          })
        else { continue }
        let screen = view.projectPoint(anchor)
        guard screen.x.isFinite, screen.y.isFinite, screen.z >= 0, screen.z <= 1 else { continue }
        points[zone] = CGPoint(x: CGFloat(screen.x), y: CGFloat(screen.y))
      }
      overlay.project(points)
    }
  }
}

@MainActor enum GripSceneBuilder {
  static func vector(_ v: SIMD3<Double>) -> SCNVector3 {
    SCNVector3(Float(v.x), Float(v.y), Float(v.z))
  }
  static func scene(pose: GripPose, showBall: Bool = true) -> SCNScene {
    let scene = SCNScene()
    let root = scene.rootNode
    let license = SCNNode()
    license.name = "Hand mesh provenance — supplied Blender rig\n" + GripHandAsset.licenseText
    root.addChildNode(license)
    let group = SCNNode()
    group.name = "hand-and-ball"
    group.scale = SCNVector3(pose.handedness == .left ? -1 : 1, 1, 1)
    root.addChildNode(group)
    let geometry = mesh(vertices: pose.vertices, indices: pose.indices)
    let skin = SCNMaterial()
    skin.lightingModel = .physicallyBased
    skin.diffuse.contents = UIColor.white
    skin.roughness.contents = 0.72
    skin.metalness.contents = 0
    geometry.materials = [skin]
    let sourceHand = try? GripHandAsset.load()
    let pressure =
      sourceHand.map { GripPoseSolver.contactPressureWeights(hand: $0, pose: pose) }
      ?? Array(repeating: 0, count: pose.vertices.count)
    let normalSurface = pressure.map { load -> SIMD4<Float> in
      let weight = Float(load)
      return SIMD4(0.70 + 0.055 * weight, 0.57 + 0.065 * weight, 0.46 + 0.065 * weight, 1)
    }
    let colorSource = colorSource(normalSurface)
    let skinGeometry = SCNGeometry(
      sources: geometry.sources + [colorSource], elements: geometry.elements)
    skinGeometry.materials = [skin]
    let hand = SCNNode(geometry: skinGeometry)
    hand.name = "measured-hand"
    group.addChildNode(hand)
    if showBall, let asset = try? GripBallAsset.load() {
      let ballGeometry = mesh(
        vertices: asset.vertices.map { SIMD3($0[0], $0[1], $0[2]) }, indices: asset.indices,
        uv: asset.uv, suppliedNormals: asset.normals)
      let material = SCNMaterial()
      material.lightingModel = .physicallyBased
      material.diffuse.contents =
        asset.textureURL.flatMap { UIImage(contentsOfFile: $0.path) } ?? UIImage()
      material.roughness.contents = 0.85
      if let url = asset.normalTextureURL {
        material.normal.contents = UIImage(contentsOfFile: url.path)
        material.normal.intensity = 1
      }
      if let url = asset.materialTextureURL, let map = UIImage(contentsOfFile: url.path) {
        material.roughness.contents = map
        material.roughness.textureComponents = .green
        material.metalness.contents = map
        material.metalness.textureComponents = .blue
      }
      ballGeometry.materials = [material]
      let ball = SCNNode(geometry: ballGeometry)
      ball.name = "regulation-baseball"
      ball.position = vector(pose.ballCenter)
      let q = pose.ballRotation.vector
      ball.simdOrientation = simd_quatf(
        ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
      if let threads = raisedBallGeometry?.copy() as? SCNGeometry {
        let threadMaterial = SCNMaterial()
        threadMaterial.lightingModel = .physicallyBased
        threadMaterial.diffuse.contents = UIColor(red: 0.65, green: 0.025, blue: 0.045, alpha: 1)
        threadMaterial.roughness.contents = 0.85
        threadMaterial.metalness.contents = 0
        threads.materials = [threadMaterial]
        let stitchNode = SCNNode(geometry: threads)
        stitchNode.name = "original-ball-raised-stitches"
        stitchNode.categoryBitMask = 2
        ball.addChildNode(stitchNode)
      }
      group.addChildNode(ball)
    }
    let markers = SCNNode()
    markers.name = "contact-points"
    group.addChildNode(markers)
    for finger in pose.fingers
    where showBall && finger.contact
      && !(pose.pitch == .circleChange && finger.finger == .index)
    {
      guard let sourceHand else { continue }
      let contact = GripPoseSolver.skinContact(
        hand: sourceHand, vertices: pose.vertices,
        finger: finger.finger, center: pose.ballCenter)
      let normal = simd_normalize(contact - pose.ballCenter)
      let dot = SCNNode(geometry: SCNSphere(radius: 1.3))
      dot.position = vector(pose.ballCenter + normal * 37)
      dot.geometry?.firstMaterial?.diffuse.contents = UIColor.systemMint
      dot.geometry?.firstMaterial?.emission.contents = UIColor.systemMint.withAlphaComponent(0.5)
      markers.addChildNode(dot)
    }
    let camera = SCNNode()
    camera.name = "camera"
    camera.camera = SCNCamera()
    camera.camera?.fieldOfView = 40
    camera.camera?.zNear = 1
    camera.camera?.zFar = 2000
    camera.position = showBall ? SCNVector3(-170, 155, 260) : SCNVector3(-170, 120, 340)
    camera.look(at: showBall ? SCNVector3(0, 60, 15) : SCNVector3(0, 80, 0))
    root.addChildNode(camera)
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 180
    ambient.light?.color = UIColor(white: 0.85, alpha: 1)
    root.addChildNode(ambient)
    for (position, intensity) in [
      (SCNVector3(-120, 230, 250), CGFloat(1250)), (SCNVector3(180, 80, -170), CGFloat(600)),
    ] {
      let light = SCNNode()
      light.light = SCNLight()
      light.light?.type = .directional
      light.light?.intensity = intensity
      if intensity > 1000 {
        light.light?.castsShadow = true
        light.light?.shadowRadius = 4
        light.light?.shadowColor = UIColor.black.withAlphaComponent(0.18)
        light.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        light.light?.orthographicScale = 220
      }
      light.position = position
      light.look(at: SCNVector3(0, 60, 15))
      root.addChildNode(light)
    }
    return scene
  }
  #if DEBUG
    /// Render actual mesh views into a review sheet; no image-generated stand-in.
    static func reviewSheet(profile: HandProfile) throws -> UIImage {
      let open = try GripPoseSolver.openHand(profile: profile)
      let bent = try GripPoseSolver.openHand(profile: profile, flexion: 0.6)
      let studio = scene(pose: open, showBall: false)
      let original = studio.rootNode.childNode(withName: "hand-and-ball", recursively: false)!
      original.removeFromParentNode()
      let curled = scene(pose: bent, showBall: false).rootNode.childNode(
        withName: "hand-and-ball", recursively: false)!
      for (i, angle) in [0.0, -Double.pi / 2, Double.pi, 0.4].enumerated() {
        let model = (i == 3 ? curled : original).clone()
        model.pivot = SCNMatrix4MakeTranslation(0, 80, 0)
        model.position = SCNVector3(Float([-190, -65, 65, 190][i]), 80, 0)
        model.eulerAngles.y = Float(angle)
        studio.rootNode.addChildNode(model)
      }
      studio.background.contents = UIColor(white: 0.16, alpha: 1)
      let camera = studio.rootNode.childNode(withName: "camera", recursively: false)!
      camera.position = SCNVector3(0, 80, 600)
      camera.look(at: SCNVector3(0, 80, 0))
      camera.camera?.usesOrthographicProjection = true
      camera.camera?.orthographicScale = 120
      let renderer = SCNRenderer(device: nil, options: nil)
      renderer.scene = studio
      renderer.pointOfView = camera
      return renderer.snapshot(
        atTime: 0, with: CGSize(width: 1600, height: 700), antialiasingMode: .multisampling4X)
    }
  #endif
  static func colorSource(_ colors: [SIMD4<Float>]) -> SCNGeometrySource {
    SCNGeometrySource(
      data: colors.withUnsafeBytes { Data($0) }, semantic: .color,
      vectorCount: colors.count, usesFloatComponents: true, componentsPerVector: 4,
      bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
  }
  static func colored(
    _ base: SCNGeometry, surface: GripZoneSurface, severity: GripSeverityMap?,
    pressure: [Double]? = nil
  )
    -> SCNGeometry
  {
    let skin = SIMD3<Float>(0.70, 0.57, 0.46)
    let baseColors = base.sources(for: .color).first
    let colors = surface.feedbackWeights.enumerated().map { vertex, weights -> SIMD4<Float> in
      var color = skin
      if let source = baseColors {
        color = source.data.withUnsafeBytes { bytes in
          let offset = source.dataOffset + vertex * source.dataStride
          return SIMD3(
            bytes.loadUnaligned(fromByteOffset: offset, as: Float.self),
            bytes.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
            bytes.loadUnaligned(fromByteOffset: offset + 8, as: Float.self))
        }
      }
      if let pressure, pressure.indices.contains(vertex), severity == nil {
        let tint = GripPoseSolver.pressureColor(pressure[vertex])
        return SIMD4(tint.x, tint.y, tint.z, 1)
      }
      for (i, zone) in GripZoneSurface.zones.enumerated() {
        guard let band = GripSeverityBand.band(severity?[zone]) else { continue }
        let tint: SIMD3<Float>
        switch band {
        case .green: tint = SIMD3(0.18, 0.78, 0.42)
        case .yellow: tint = SIMD3(1.0, 0.72, 0.12)
        case .red: tint = SIMD3(0.95, 0.16, 0.17)
        }
        let alpha = Float(weights[i]) * 0.88
        color = color * (1 - alpha) + tint * alpha
      }
      return SIMD4(color.x, color.y, color.z, 1)
    }
    let geometry = SCNGeometry(
      sources: base.sources.filter { $0.semantic != .color } + [colorSource(colors)],
      elements: base.elements)
    geometry.materials = base.materials
    return geometry
  }
  /// A white contour, independent of diagnostic color, follows the selected surface region.
  static func outline(
    vertices: [SIMD3<Double>], indices: [UInt32], surface: GripZoneSurface, zone: GripZoneID
  ) -> SCNNode {
    let zi = GripZoneSurface.zones.firstIndex(of: zone)!
    var points: [SCNVector3] = []
    for face in stride(from: 0, to: indices.count, by: 3) {
      let ids = (0..<3).map { Int(indices[face + $0]) }
      let p = ids.map { vertices[$0] }
      let normal = simd_cross(p[1] - p[0], p[2] - p[0])
      guard simd_length(normal) > 1e-10 else { continue }
      let offset = simd_normalize(normal) * 0.35
      var cuts: [SIMD3<Double>] = []
      for edge in 0..<3 {
        let next = (edge + 1) % 3
        let a = surface.weights[ids[edge]][zi]
        let b = surface.weights[ids[next]][zi]
        if (a < 0.35) != (b < 0.35) {
          cuts.append(p[edge] + (p[next] - p[edge]) * ((0.35 - a) / (b - a)) + offset)
        }
      }
      if cuts.count == 2 { points.append(contentsOf: cuts.map(vector)) }
    }
    let geometry = SCNGeometry(
      sources: [SCNGeometrySource(vertices: points)],
      elements: [
        SCNGeometryElement(indices: (0..<UInt32(points.count)).map { $0 }, primitiveType: .line)
      ])
    let material = SCNMaterial()
    material.lightingModel = .constant
    material.diffuse.contents = UIColor.white
    material.isDoubleSided = true
    geometry.materials = [material]
    let node = SCNNode(geometry: geometry)
    node.name = "zone-selection"
    node.categoryBitMask = 2
    return node
  }
  static func mesh(
    vertices: [SIMD3<Double>], indices: [UInt32], uv: [[Double]]? = nil,
    suppliedNormals: [[Double]]? = nil
  )
    -> SCNGeometry
  {
    var normals = Array(repeating: SIMD3<Double>.zero, count: vertices.count)
    for i in stride(from: 0, to: indices.count, by: 3) {
      let a = Int(indices[i])
      let b = Int(indices[i + 1])
      let c = Int(indices[i + 2])
      let normal = simd_cross(vertices[b] - vertices[a], vertices[c] - vertices[a])
      normals[a] += normal
      normals[b] += normal
      normals[c] += normal
    }
    if let suppliedNormals, suppliedNormals.count == vertices.count {
      normals = suppliedNormals.map { SIMD3($0[0], $0[1], $0[2]) }
    }
    var sources = [
      SCNGeometrySource(vertices: vertices.map(vector)),
      SCNGeometrySource(
        normals: normals.map {
          vector(simd_length($0) > 1e-10 ? simd_normalize($0) : SIMD3(0, 0, 1))
        }),
    ]
    if let uv {
      // UIImage-backed SceneKit textures use these glTF UVs directly.
      // An extra V flip breaks atlas boundaries and disagrees with seam fitting.
      sources.append(
        SCNGeometrySource(textureCoordinates: uv.map { CGPoint(x: $0[0], y: $0[1]) }))
    }
    return SCNGeometry(
      sources: sources, elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
  }
}
