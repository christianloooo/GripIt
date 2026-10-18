import GripItScannerCore
import SceneKit
import XCTest

@testable import GripIt

final class GripViewerTests: XCTestCase {
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
      attachment.name = "Stitch landmark \(anchor)"
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
        red, 10, "The rendered stitch must coincide with seam landmark \(anchor)")
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
      XCTAssertNotNil(scene.rootNode.childNode(withName: "thumb-nail", recursively: true))
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
  @MainActor func testAbsentAndMissingSeverityKeepSkinColorAndOmittedPalmHasNoOutline() throws {
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
    XCTAssertEqual(
      normal.sources(for: .color).first?.data, palmOnly.sources(for: .color).first?.data)
    let colored = GripSceneBuilder.colored(base, surface: surface, severity: .sample)
    XCTAssertNotEqual(
      normal.sources(for: .color).first?.data, colored.sources(for: .color).first?.data)
    let palm = GripSceneBuilder.outline(
      vertices: pose.vertices, indices: pose.indices, surface: surface, zone: .palm)
    XCTAssertEqual(palm.geometry?.sources(for: .vertex).first?.vectorCount, 0)
  }
}

extension GripViewerTests {
  @MainActor func testNeutralReviewUsesRealPersonalizedMeshWithoutBall() throws {
    let pose = try GripPoseSolver.openHand(profile: SampleHandProfiles.averageRight())
    let scene = GripSceneBuilder.scene(pose: pose, showBall: false)
    XCTAssertNil(scene.rootNode.childNode(withName: "regulation-baseball", recursively: true))
    XCTAssertNotNil(scene.rootNode.childNode(withName: "measured-hand", recursively: true))
    for finger in GripFinger.allCases {
      let nail = try XCTUnwrap(
        scene.rootNode.childNode(withName: "\(finger.rawValue)-nail", recursively: true))
      let normal = nail.simdOrientation.act(SIMD3<Float>(0, 0, 1))
      XCTAssertLessThan(normal.z, -0.5, "Neutral nails belong on the dorsal surface, never the pad")
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
  @MainActor func testNailsRemainAttachedToActualSkinThroughFlexion() throws {
    for amount in [0.0, 0.6] {
      let pose = try GripPoseSolver.openHand(
        profile: SampleHandProfiles.averageRight(), flexion: amount)
      let scene = GripSceneBuilder.scene(pose: pose, showBall: false)
      for finger in GripFinger.allCases {
        let nail = try XCTUnwrap(
          scene.rootNode.childNode(withName: "\(finger.rawValue)-nail", recursively: true))
        let source = try XCTUnwrap(nail.geometry?.sources(for: .vertex).first)
        for i in 0..<source.vectorCount {
          let v = source.data.withUnsafeBytes { bytes -> SIMD3<Float> in
            let offset = source.dataOffset + i * source.dataStride
            return SIMD3(
              bytes.loadUnaligned(fromByteOffset: offset, as: Float.self),
              bytes.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
              bytes.loadUnaligned(fromByteOffset: offset + 8, as: Float.self))
          }
          let p = nail.simdTransform * SIMD4(v.x, v.y, v.z, 1)
          let point = SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z))
          let gap = pose.vertices.map { simd_distance($0, point) }.min()!
          XCTAssertLessThan(
            gap, 0.07, "Nail patch must follow the posed skin rather than float above it")
        }
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
