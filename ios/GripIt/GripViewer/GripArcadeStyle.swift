import GripItScannerCore
import SceneKit
import UIKit
import simd

extension GripSceneBuilder {
  /// Matte materials and a clean seam-only ball keep the measured shape legible.
  @MainActor static func applyArcadeStyle(_ scene: SCNScene, pose: GripPose) {
    scene.background.contents = UIColor.clear
    if let hand = scene.rootNode.childNode(withName: "measured-hand", recursively: true) {
      hand.geometry?.firstMaterial?.lightingModel = .lambert
      hand.geometry?.firstMaterial?.specular.contents = UIColor.black
      hand.geometry?.firstMaterial?.roughness.contents = 1
      var normals = Array(repeating: SIMD3<Double>.zero, count: pose.vertices.count)
      for i in stride(from: 0, to: pose.indices.count, by: 3) {
        let a = Int(pose.indices[i])
        let b = Int(pose.indices[i + 1])
        let c = Int(pose.indices[i + 2])
        let n = simd_cross(pose.vertices[b] - pose.vertices[a], pose.vertices[c] - pose.vertices[a])
        normals[a] += n
        normals[b] += n
        normals[c] += n
      }
      let expanded = pose.vertices.enumerated().map { i, p in
        p + (simd_length(normals[i]) > 0 ? simd_normalize(normals[i]) * 0.45 : .zero)
      }
      let geometry = mesh(vertices: expanded, indices: pose.indices)
      let material = SCNMaterial()
      material.lightingModel = .constant
      material.diffuse.contents = UIColor(red: 0.025, green: 0.09, blue: 0.07, alpha: 1)
      material.cullMode = .front
      material.isDoubleSided = false
      geometry.materials = [material]
      let outline = SCNNode(geometry: geometry)
      outline.name = "arcade-hand-outline"
      outline.categoryBitMask = 2
      hand.addChildNode(outline)
    }
    // Preserve the supplied ball's original UVs and PBR maps. Arcade treatment
    // applies to the hand; the baseball keeps its recognizable source material.
  }
  @MainActor static let raisedBallGeometry: SCNGeometry? = {
    guard let asset = try? GripBallStitchAsset.load() else { return nil }
    return mesh(vertices: asset.vertices.map { SIMD3($0[0], $0[1], $0[2]) },
      indices: asset.indices, suppliedNormals: asset.normals)
  }()
}
