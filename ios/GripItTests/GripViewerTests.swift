import GripItScannerCore
import SceneKit
import XCTest

@testable import GripIt

final class GripViewerTests: XCTestCase {
  @MainActor func testFeedbackNodesShowRulesAndReuseTheFittedScene() throws {
    let pose = try GripPoseSolver.solve(profile: SampleHandProfiles.averageRight(), pitch: .fourSeam)
    let render = try GripRenderState(pose: pose)
    var draft = ThrowSessionDraft(source: .sample)
    draft.rows = [RapsodoPhotoFixture.baseball.makeDraft()]
    let records = try NativeFocusEngine.records(draft, pitch: .fourSeam, profileId: "nodes")
    let assessment = try NativeFocusEngine.assess(pitch: .fourSeam, records: records,
      zones: PitchGrip.fourSeam.zoneTemplates, gripPlanId: "nodes")
    let view = SCNView(frame: CGRect(x: 0, y: 0, width: 390, height: 440))
    let coordinator = GripSceneView.Coordinator()
    coordinator.update(view, pose: pose, contacts: false, camera: .threeQuarter, reset: 0,
      plan: render.plan, render: render, severity: assessment.severityMap, selected: .thumbPad,
      annotations: true, arcade: true, assessment: assessment)
    defer { GripSceneView.dismantleUIView(view, coordinator: coordinator) }
    let overlay = try XCTUnwrap(coordinator.graphOverlay)
    overlay.layoutIfNeeded()
    func descendants(_ view: UIView) -> [UIView] {
      view.subviews.flatMap { [$0] + descendants($0) }
    }
    let labels = descendants(overlay).compactMap { $0 as? UILabel }
    let instruction = try XCTUnwrap(labels.first { $0.accessibilityIdentifier == "grip-node-instruction" })
    XCTAssertEqual(instruction.text, assessment.changeToTry)
    let reading = try XCTUnwrap(labels.first { $0.accessibilityIdentifier == "grip-node-effort" })
    XCTAssertTrue(reading.text?.contains("1:56") == true)
    XCTAssertFalse(labels.contains { $0.text?.contains("EFFORT") == true })
    let scene = view.scene
    let vertices = coordinator.hand?.geometry?.sources(for: .vertex).first
    coordinator.update(view, pose: pose, contacts: false, camera: .back, reset: 1,
      plan: render.plan, render: render, severity: assessment.severityMap, selected: .pinky,
      annotations: true, arcade: true, assessment: assessment)
    XCTAssertTrue(view.scene === scene)
    XCTAssertTrue(vertices === coordinator.hand?.geometry?.sources(for: .vertex).first)
    XCTAssertEqual(instruction.text, "No throw finding for this area.")
  }

  @MainActor func testChangeupReadsCurrentFastballDraftFromTheSameStudio() async throws {
    let profile = try SampleHandProfiles.averageRight()
    let studio = GripStudioSession(profile: profile)
    let fastballFit = try await studio.fitted(.fourSeam)
    let changeupFit = try await studio.fitted(.circleChange)
    let fastball = studio.training(for: fastballFit)
    let changeup = studio.training(for: changeupFit)
    changeup.replaceDraft(sample: true)
    let alone = try XCTUnwrap(changeup.assessment())
    guard case .object(let withoutBaseline) = alone.extensions["gripFeedback"] else {
      return XCTFail("Missing feedback")
    }
    XCTAssertEqual(withoutBaseline["kind"], .string("baseline"))
    fastball.replaceDraft(sample: true)
    let compared = try XCTUnwrap(changeup.assessment())
    guard case .object(let withBaseline) = compared.extensions["gripFeedback"] else {
      return XCTFail("Missing feedback")
    }
    XCTAssertNotEqual(withBaseline["kind"], .string("baseline"))
    fastball.draft.rows[0].velocityMph = "invalid"
    let invalid = try XCTUnwrap(changeup.assessment())
    guard case .object(let ignoredInvalidBaseline) = invalid.extensions["gripFeedback"] else {
      return XCTFail("Missing feedback")
    }
    XCTAssertEqual(ignoredInvalidBaseline["kind"], .string("baseline"))
  }

  @MainActor func testSavedScanKeepsMeasurementsAndSampleCannotOverwriteIt() throws {
    let sample = try SampleHandProfiles.averageRight()
    let scan = HandProfile(profileId: "saved-real-scan", createdAt: sample.createdAt,
      handedness: .left, measurements: sample.measurements, landmarks: sample.landmarks,
      capture: CaptureMetadata(method: "true-depth-mediapipe", coverage: sample.capture.coverage,
        calibration: sample.capture.calibration, confidence: sample.capture.confidence))
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("profile.json")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    XCTAssertNil(SavedHandProfile.load(from: file))
    try SavedHandProfile.save(scan, to: file)
    XCTAssertEqual(SavedHandProfile.load(from: file), scan)
    try SavedHandProfile.save(sample, to: file)
    XCTAssertEqual(SavedHandProfile.load(from: file), scan)
    let directory = file.deletingLastPathComponent()
    let oldExport = directory.appendingPathComponent("gripit-hand-old.json")
    try HandProfileCodec.encode(scan).write(to: oldExport)
    try HandProfileCodec.encode(sample).write(to: directory.appendingPathComponent("gripit-hand-demo.json"))
    let restored = directory.appendingPathComponent("restored.json")
    XCTAssertEqual(SavedHandProfile.latest(exportDirectory: directory, savedFile: restored), scan)
    XCTAssertEqual(SavedHandProfile.load(from: restored), scan)
  }
  @MainActor func testGraphNodesSelectInstructionsAndFollowCameraWithoutRebuilding() throws {
    let pose = try GripPoseSolver.solve(
      profile: SampleHandProfiles.averageRight(), pitch: .fourSeam)
    let plan = GripPlan(pose: pose)
    let view = SCNView(frame: CGRect(x: 0, y: 0, width: 400, height: 580))
    let coordinator = GripSceneView.Coordinator()
    var picked: GripZoneID?
    var closed = false
    coordinator.onZoneSelect = { picked = $0 }
    coordinator.onZoneDismiss = { closed = true }
    coordinator.update(
      view, pose: pose, contacts: false, camera: .threeQuarter, reset: 0,
      plan: plan, severity: nil, selected: .middlePad, pressure: true, annotations: true,
      arcade: true)
    view.layoutIfNeeded()
    let overlay = try XCTUnwrap(coordinator.graphOverlay)
    overlay.layoutIfNeeded()
    let nodes = overlay.subviews.compactMap { $0 as? UIButton }
    XCTAssertEqual(nodes.count, 7)
    let wrist = try XCTUnwrap(nodes.first { $0.accessibilityIdentifier == "grip-node-wrist" })
    wrist.sendActions(for: .touchUpInside)
    XCTAssertEqual(picked, .wrist)
    let geometry = coordinator.hand?.geometry?.sources(for: .vertex).first
    let scene = view.scene
    coordinator.update(
      view, pose: pose, contacts: false, camera: .threeQuarter, reset: 0,
      plan: plan, severity: nil, selected: .wrist, pressure: true, annotations: true, arcade: true)
    overlay.layoutIfNeeded()
    func descendants(_ view: UIView) -> [UIView] {
      view.subviews.flatMap { [$0] + descendants($0) }
    }
    let views = descendants(overlay)
    let body = try XCTUnwrap(
      views.first { $0.accessibilityIdentifier == "grip-node-instruction" } as? UILabel)
    XCTAssertEqual(body.text, plan.zones.first { $0.zoneId == .wrist }?.instruction)
    let effort = try XCTUnwrap(
      views.first { $0.accessibilityIdentifier == "grip-node-effort" } as? UILabel)
    XCTAssertTrue(effort.text?.contains("FIRM") == true)
    XCTAssertEqual(
      views.filter { $0.accessibilityIdentifier == "grip-instruction-card" && !$0.isHidden }.count,
      1)
    _ = view.snapshot()
    coordinator.projectAnnotations()
    overlay.layoutIfNeeded()
    let before = nodes.map(\.center)
    coordinator.update(
      view, pose: pose, contacts: false, camera: .thumbSide, reset: 1,
      plan: plan, severity: nil, selected: .wrist, pressure: true, annotations: true, arcade: true)
    SCNTransaction.flush()
    _ = view.snapshot()
    coordinator.projectAnnotations()
    overlay.layoutIfNeeded()
    let movement = zip(before, nodes).map { hypot($0.0.x - $0.1.center.x, $0.0.y - $0.1.center.y) }
      .max()!
    XCTAssertGreaterThan(movement, 1, "Projected skin anchors must follow camera rotation")
    XCTAssertTrue(view.scene === scene)
    XCTAssertTrue(geometry === coordinator.hand?.geometry?.sources(for: .vertex).first)
    for node in nodes {
      XCTAssertGreaterThanOrEqual(node.bounds.width, 44)
      XCTAssertTrue(overlay.bounds.contains(node.frame))
    }
    let close = try XCTUnwrap(
      views.first { $0.accessibilityIdentifier == "close-grip-instruction" } as? UIButton)
    close.sendActions(for: .touchUpInside)
    XCTAssertTrue(closed)
    XCTAssertNotNil(scene?.rootNode.childNode(withName: "arcade-hand-outline", recursively: true))
    let ball = try XCTUnwrap(
      scene?.rootNode.childNode(withName: "regulation-baseball", recursively: true)?.geometry?
        .firstMaterial)
    XCTAssertEqual(ball.lightingModel, .physicallyBased)
    XCTAssertTrue(ball.normal.contents is UIImage)
    let raised = try XCTUnwrap(GripSceneBuilder.raisedBallGeometry)
    let source = try XCTUnwrap(raised.sources(for: .vertex).first)
    var maximumRadius: Float = 0
    source.data.withUnsafeBytes { bytes in
      for i in 0..<source.vectorCount {
        let offset = source.dataOffset + i * source.dataStride
        let x = bytes.loadUnaligned(fromByteOffset: offset, as: Float.self)
        let y = bytes.loadUnaligned(fromByteOffset: offset + 4, as: Float.self)
        let z = bytes.loadUnaligned(fromByteOffset: offset + 8, as: Float.self)
        maximumRadius = max(maximumRadius, sqrt(x*x + y*y + z*z))
      }
    }
    XCTAssertGreaterThan(maximumRadius, 37, "Stitches must protrude above the 36.5 mm leather")
    let card = try XCTUnwrap(views.first { $0.accessibilityIdentifier == "grip-instruction-card" })
    XCTAssertGreaterThanOrEqual(card.frame.minY - wrist.frame.maxY, 24)

    GripSceneView.dismantleUIView(view, coordinator: coordinator)
    XCTAssertNil(coordinator.displayLink)
    XCTAssertNil(overlay.superview)
  }
  @MainActor func testPressurePreviewUsesContinuousPineShadingAndExportsActualScenes() throws {
    let asset = try GripHandAsset.load()
    for pitch in PitchGrip.allCases {
      let pose = try GripPoseSolver.solve(profile: SampleHandProfiles.averageRight(), pitch: pitch)
      let scene = GripSceneBuilder.scene(pose: pose)
      let hand = try XCTUnwrap(
        scene.rootNode.childNode(withName: "measured-hand", recursively: true))
      let base = try XCTUnwrap(hand.geometry)
      let surface = GripZoneSurface(pose: pose, gripPlan: GripPlan(pose: pose), hand: asset)
      let weights = GripPoseSolver.pressureShadingWeights(hand: asset, pose: pose)
      XCTAssertGreaterThan(weights.max()!, 0.5)
      XCTAssertGreaterThan(
        weights.filter { $0 > 0.2 }.count, 400,
        "Coaching shading must remain visible around the loaded finger sections")
      for i in asset.vertices.indices where asset.vertices[i][1] < -8 {
        XCTAssertGreaterThan(
          weights[i], pitch == .circleChange ? 0.6 : 0.95,
          "Every side of the wrist must show stabilization")
      }
      XCTAssertEqual(GripPoseSolver.pressureColor(0), SIMD3<Float>(repeating: 1))
      XCTAssertEqual(GripPoseSolver.pressureColor(1).x, 0.00270898, accuracy: 0.000001)
      XCTAssertEqual(GripPoseSolver.pressureColor(1).y, 0.06838485, accuracy: 0.000001)
      XCTAssertEqual(GripPoseSolver.pressureColor(1).z, 0.03630648, accuracy: 0.000001)
      let pressure = GripSceneBuilder.colored(
        base, surface: surface, severity: nil, pressure: weights)
      hand.geometry = pressure
      // An incoming Step 4 result takes precedence even if a Step 2 flag remains set.
      let diagnostics = GripSceneBuilder.colored(base, surface: surface, severity: .sample)
      let both = GripSceneBuilder.colored(
        base, surface: surface, severity: .sample, pressure: weights)
      XCTAssertEqual(
        diagnostics.sources(for: .color).first?.data, both.sources(for: .color).first?.data)
      XCTAssertNotEqual(
        pressure.sources(for: .color).first?.data, diagnostics.sources(for: .color).first?.data)
      scene.rootNode.childNode(withName: "contact-points", recursively: true)?.isHidden = true
      let camera = try XCTUnwrap(scene.rootNode.childNode(withName: "camera", recursively: false))
      camera.camera?.usesOrthographicProjection = true
      camera.camera?.orthographicScale = 100
      let renderer = SCNRenderer(device: nil, options: nil)
      renderer.scene = scene
      renderer.pointOfView = camera
      for (name, position) in [
        ("thumb", SCNVector3(290, 90, 80)), ("fingers", SCNVector3(-100, 270, 160)),
        ("palm", SCNVector3(0, 75, 300)), ("back", SCNVector3(0, 85, -290)),
      ] {
        camera.position = position
        camera.look(at: SCNVector3(0, 80, 35))
        let image = renderer.snapshot(
          atTime: 0, with: CGSize(width: 800, height: 800), antialiasingMode: .multisampling4X)
        let attachment = XCTAttachment(image: image)
        attachment.name = "\(pitch.rawValue)-pressure-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
    }
  }
  @MainActor func testSeamLandmarksLandOnVisibleRedStitches() throws {
    // Exercise the actual SceneKit geometry + UIImage UV path, independently
    // of the solver's seam-distance math. A mirrored texture must fail here.
    let pose = try GripPoseSolver.openHand(profile: SampleHandProfiles.averageRight())
    let scene = GripSceneBuilder.scene(pose: pose)
    scene.rootNode.childNode(withName: "measured-hand", recursively: true)?.isHidden = true
    for node in scene.rootNode.childNode(withName: "hand-and-ball", recursively: true)!.childNodes
    where node.name?.hasSuffix("-nail") == true { node.isHidden = true }
    let ball = try XCTUnwrap(
      scene.rootNode.childNode(withName: "regulation-baseball", recursively: true))
    ball.simdPosition = .zero
    ball.simdOrientation = simd_quatf()
    let material = ball.geometry!.firstMaterial!
    material.lightingModel = .constant
    material.normal.contents = nil
    let camera = SCNNode()
    camera.camera = SCNCamera()
    camera.camera!.usesOrthographicProjection = true
    camera.camera!.orthographicScale = 4
    camera.camera!.zNear = 0.1
    camera.camera!.zFar = 1000
    scene.rootNode.addChildNode(camera)
    let renderer = SCNRenderer(device: nil, options: nil)
    renderer.scene = scene
    renderer.pointOfView = camera
    for arcade in [false, true] {
      if arcade { GripSceneBuilder.applyArcadeStyle(scene, pose: pose) }
      material.lightingModel = .constant
      for anchor: SIMD3<Float> in [
        SIMD3(-26.84094, -2.17919, -24.63870),
        SIMD3(-18.26992, 12.53505, -29.00574),
        SIMD3(-6.37951, -34.82375, 8.88021),
        SIMD3(-1.79325, -35.16069, -9.63120),
        SIMD3(-19.94635, 25.86259, -16.29477),
        SIMD3(17.21222, -30.31248, 10.82328),
        SIMD3(13.35501, -32.35483, -10.34693),
      ] {
        camera.simdPosition = simd_normalize(anchor) * 150
        camera.look(at: SCNVector3(anchor))
        let image = renderer.snapshot(
          atTime: 0, with: CGSize(width: 96, height: 96), antialiasingMode: .multisampling4X)
        let attachment = XCTAttachment(image: image)
        attachment.name = "\(arcade ? "Arcade" : "Original") stitch landmark \(anchor)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let cg = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: 96 * 96 * 4)
        let context = try XCTUnwrap(
          CGContext(
            data: &pixels, width: 96, height: 96,
            bitsPerComponent: 8, bytesPerRow: 96 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 96, height: 96))
        var red = 0
        for y in 24..<72 {
          for x in 24..<72 {
            let i = (y * 96 + x) * 4
            if Double(pixels[i]) > Double(pixels[i + 1]) * 1.4
              && Double(pixels[i]) > Double(pixels[i + 2]) * 1.4 && pixels[i] > 60
            {
              red += 1
            }
          }
        }
        XCTAssertGreaterThan(
          red, 10, "\(arcade ? "Arcade" : "Original") stitch must coincide with seam landmark \(anchor)")
      }
    }
  }
  @MainActor func testNativeSceneContainsAuthoredHandAndTexturedRegulationBall() throws {
    let profile = try SampleHandProfiles.averageRight()
    for pitch in PitchGrip.allCases {
      let pose = try GripPoseSolver.solve(profile: profile, pitch: pitch)
      let scene = GripSceneBuilder.scene(pose: pose)
      let hand = try XCTUnwrap(
        scene.rootNode.childNode(withName: "measured-hand", recursively: true))
      let geometry = try XCTUnwrap(hand.geometry)
      XCTAssertEqual(geometry.sources(for: .vertex).first?.vectorCount, pose.vertices.count)
      XCTAssertEqual(geometry.sources(for: .normal).first?.vectorCount, pose.vertices.count)
      let ball = try XCTUnwrap(
        scene.rootNode.childNode(withName: "regulation-baseball", recursively: true))
      XCTAssertTrue(ball.geometry?.firstMaterial?.diffuse.contents is UIImage)
      XCTAssertEqual(ball.position.z, Float(pose.ballCenter.z), accuracy: 0.001)
      XCTAssertNil(scene.rootNode.childNode(withName: "thumb-nail", recursively: true))
      XCTAssertNotNil(scene.rootNode.childNode(withName: "contact-points", recursively: true))
    }
  }
  @MainActor func testLeftHandMirrorsTheWholeGripOnce() throws {
    let sample = try SampleHandProfiles.averageRight()
    let left = HandProfile(
      profileId: "left", createdAt: sample.createdAt, handedness: .left,
      measurements: sample.measurements, landmarks: [:], capture: sample.capture)
    let scene = GripSceneBuilder.scene(
      pose: try GripPoseSolver.solve(profile: left, pitch: .circleChange))
    XCTAssertEqual(
      scene.rootNode.childNode(withName: "hand-and-ball", recursively: false)?.scale.x, -1)
    XCTAssertEqual(
      scene.rootNode.childNode(withName: "measured-hand", recursively: true)?.scale.x, 1)
  }
}

extension GripViewerTests {
  @MainActor func testSeverityReusesSceneAndCameraAndSamePitchNewProfileRebuilds() throws {
    let pose = try GripPoseSolver.solve(profile: SampleHandProfiles.averageRight(), pitch: .slider)
    let coordinator = GripSceneView.Coordinator()
    let view = SCNView(frame: CGRect(x: 0, y: 0, width: 400, height: 390))
    view.allowsCameraControl = true
    XCTAssertTrue(
      view.gestureRecognizers?.contains { $0 is UIPinchGestureRecognizer } == true,
      "SceneKit must expose the pinch recognizer to attach zoom limits")
    let plan = GripPlan(pose: pose)
    coordinator.update(
      view, pose: pose, contacts: false, camera: .palm, reset: 0,
      plan: plan, severity: nil, selected: nil)
    let scene = view.scene
    let ball = scene?.rootNode.childNode(withName: "regulation-baseball", recursively: true)
    let position = view.pointOfView?.position
    let source = coordinator.hand?.geometry?.sources(for: .vertex).first
    coordinator.update(
      view, pose: pose, contacts: false, camera: .palm, reset: 0,
      plan: plan, severity: .sample, selected: .thumbPad)
    XCTAssertTrue(view.scene === scene)
    XCTAssertTrue(
      ball === view.scene?.rootNode.childNode(withName: "regulation-baseball", recursively: true))
    XCTAssertTrue(source === coordinator.hand?.geometry?.sources(for: .vertex).first)
    XCTAssertEqual(view.pointOfView?.position.x, position?.x)
    let outline = try XCTUnwrap(
      coordinator.hand?.childNode(withName: "zone-selection", recursively: false))
    XCTAssertGreaterThan(outline.geometry?.sources(for: .vertex).first?.vectorCount ?? 0, 0)
    XCTAssertEqual(outline.categoryBitMask, 2)
    coordinator.update(
      view, pose: pose, contacts: false, camera: .palm, reset: 0,
      plan: plan, severity: nil, selected: nil, pressure: true)
    let before = coordinator.hand?.geometry?.sources(for: .color).first?.data
    var payload = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
    var zones = try XCTUnwrap(payload["zones"] as? [[String: Any]])
    for i in zones.indices where zones[i]["zoneId"] as? String == "wrist" {
      zones[i]["pressure"] = "none"
      var highlight = zones[i]["highlight"] as! [String: Any]
      highlight["intensity"] = "none"
      zones[i]["highlight"] = highlight
    }
    payload["zones"] = zones
    let changedPlan = try JSONDecoder().decode(
      GripPlan.self, from: JSONSerialization.data(withJSONObject: payload))
    coordinator.update(
      view, pose: pose, contacts: false, camera: .palm, reset: 0,
      plan: changedPlan, severity: nil, selected: nil, pressure: true)
    XCTAssertTrue(view.scene === scene, "Editing an effort instruction must reuse the fitted model")
    XCTAssertTrue(source === coordinator.hand?.geometry?.sources(for: .vertex).first)
    XCTAssertNotEqual(
      before, coordinator.hand?.geometry?.sources(for: .color).first?.data,
      "A changed wrist instruction must immediately change the visible highlight")
    XCTAssertEqual(view.pointOfView?.position.x, position?.x)
    let next = try GripPoseSolver.solve(profile: SampleHandProfiles.averageRight(), pitch: .slider)
    coordinator.update(
      view, pose: next, contacts: false, camera: .palm, reset: 0,
      plan: GripPlan(pose: next), severity: nil, selected: nil)
    XCTAssertFalse(
      view.scene === scene, "A new fitted pose of the same pitch must replace the old hand")
    view.pointOfView?.simdWorldPosition = SIMD3(0, 60, 16)
    coordinator.clampZoom(view)
    XCTAssertEqual(
      simd_length(view.pointOfView!.simdWorldPosition - SIMD3(0, 60, 15)), 150, accuracy: 0.01)
  }
  @MainActor func testAbsentAndMissingSeverityKeepSkinColorAndAllRegionsAreSelectable() throws {
    let pose = try GripPoseSolver.solve(profile: SampleHandProfiles.averageRight(), pitch: .slider)
    let scene = GripSceneBuilder.scene(pose: pose)
    let hand = try XCTUnwrap(scene.rootNode.childNode(withName: "measured-hand", recursively: true))
    let surface = GripZoneSurface(
      pose: pose, gripPlan: GripPlan(pose: pose), hand: try GripHandAsset.load())
    let base = try XCTUnwrap(hand.geometry)
    let normal = GripSceneBuilder.colored(base, surface: surface, severity: nil)
    let missing = GripSceneBuilder.colored(base, surface: surface, severity: GripSeverityMap([:]))
    XCTAssertEqual(
      normal.sources(for: .color).first?.data, missing.sources(for: .color).first?.data)
    let palmOnly = GripSceneBuilder.colored(
      base, surface: surface, severity: GripSeverityMap(["palm": 1]))
    XCTAssertNotEqual(
      normal.sources(for: .color).first?.data, palmOnly.sources(for: .color).first?.data)
    let colored = GripSceneBuilder.colored(base, surface: surface, severity: .sample)
    XCTAssertNotEqual(
      normal.sources(for: .color).first?.data, colored.sources(for: .color).first?.data)
    let palm = GripSceneBuilder.outline(
      vertices: pose.vertices, indices: pose.indices, surface: surface, zone: .palm)
    XCTAssertGreaterThan(palm.geometry?.sources(for: .vertex).first?.vectorCount ?? 0, 0)
  }
}

extension GripViewerTests {
  @MainActor func testNeutralReviewUsesRealPersonalizedMeshWithoutBall() throws {
    let pose = try GripPoseSolver.openHand(profile: SampleHandProfiles.averageRight())
    let scene = GripSceneBuilder.scene(pose: pose, showBall: false)
    XCTAssertNil(scene.rootNode.childNode(withName: "regulation-baseball", recursively: true))
    XCTAssertNotNil(scene.rootNode.childNode(withName: "measured-hand", recursively: true))
    for finger in GripFinger.allCases {
      XCTAssertNil(scene.rootNode.childNode(withName: "\(finger.rawValue)-nail", recursively: true))
    }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("GripIt-Hand.scn")
    XCTAssertTrue(scene.write(to: file, options: nil, delegate: nil, progressHandler: nil))
    XCTAssertTrue(
      try SCNScene(url: file, options: nil).rootNode.childNodes.contains {
        $0.name?.contains("Rigged Hands.blend") == true
      })
    XCTAssertNotNil(
      try SCNScene(url: file, options: nil).rootNode.childNode(
        withName: "measured-hand", recursively: true))
  }
}

extension GripViewerTests {
  @MainActor func testRemovingNailsKeepsTheFullFingerMeshThroughFlexion() throws {
    for amount in [0.0, 0.6] {
      let pose = try GripPoseSolver.openHand(
        profile: SampleHandProfiles.averageRight(), flexion: amount)
      let scene = GripSceneBuilder.scene(pose: pose, showBall: false)
      let geometry = try XCTUnwrap(
        scene.rootNode.childNode(withName: "measured-hand", recursively: true)?.geometry)
      XCTAssertEqual(geometry.sources(for: .vertex).first?.vectorCount, pose.vertices.count)
      XCTAssertEqual(geometry.elements.first?.primitiveCount, pose.indices.count / 3)
      for finger in GripFinger.allCases {
        XCTAssertNil(
          scene.rootNode.childNode(withName: "\(finger.rawValue)-nail", recursively: true))
      }
    }
  }
}

extension GripViewerTests {
  @MainActor func testSuppliedBaseballRendersAllPBRMapsAndSmoothNormals() throws {
    let pose = try GripPoseSolver.solve(
      profile: SampleHandProfiles.averageRight(), pitch: .fourSeam)
    let scene = GripSceneBuilder.scene(pose: pose)
    let ball = try XCTUnwrap(
      scene.rootNode.childNode(withName: "regulation-baseball", recursively: true))
    let material = try XCTUnwrap(ball.geometry?.firstMaterial)
    XCTAssertTrue(material.diffuse.contents is UIImage)
    XCTAssertTrue(material.normal.contents is UIImage)
    XCTAssertTrue(material.roughness.contents is UIImage)
    XCTAssertTrue(material.metalness.contents is UIImage)
    XCTAssertEqual(material.roughness.textureComponents, .green)
    XCTAssertEqual(material.metalness.textureComponents, .blue)
    XCTAssertEqual((material.normal.contents as? UIImage)?.size.width, 2048)
    // The displayed atlas must match the UVs used to sample source stitch contacts.
    let asset = try GripBallAsset.load()
    let uv = try XCTUnwrap(ball.geometry?.sources(for: .texcoord).first)
    for i in 0..<uv.vectorCount {
      for axis in 0..<2 {
        let value = uv.data.withUnsafeBytes { bytes -> Double in
          let offset = uv.dataOffset + i * uv.dataStride + axis * uv.bytesPerComponent
          if uv.bytesPerComponent == 4 {
            return Double(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self))
          }
          return bytes.loadUnaligned(fromByteOffset: offset, as: Double.self)
        }
        XCTAssertEqual(value, asset.uv[i][axis], accuracy: 0.000001)
      }
    }
  }
}
