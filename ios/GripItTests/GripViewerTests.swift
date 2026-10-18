import GripItScannerCore
import SceneKit
import XCTest

@testable import GripIt

final class GripViewerTests: XCTestCase {
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
        $0.name?.contains("Copyright (c) 2019 Amazon") == true
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
