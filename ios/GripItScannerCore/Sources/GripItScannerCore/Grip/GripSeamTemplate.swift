import simd

/// Landmarks on the bundled clean baseball, in its original texture/mesh frame.
/// Keep each finger on its specified stretch of stitching. Searching the whole
/// sphere independently produces equally scored but visibly flipped grips.
/// These coordinates must be reviewed again if the baseball asset is replaced.
enum GripSeamTemplate {
  static func anchor(_ pitch: PitchGrip, _ finger: GripFinger) -> SIMD3<Double>? {
    switch (pitch, finger) {
    case (.fourSeam, .index): SIMD3(-26.84094, -2.17919, -24.63870)
    case (.fourSeam, .middle): SIMD3(-18.26992, 12.53505, -29.00574)
    case (.twoSeam, .index): SIMD3(-6.37951, -34.82375, 8.88021)
    case (.twoSeam, .middle): SIMD3(-1.79325, -35.16069, -9.63120)
    case (.slider, .middle): SIMD3(-19.94635, 25.86259, -16.29477)
    case (.circleChange, .middle): SIMD3(17.21222, -30.31248, 10.82328)
    case (.circleChange, .ring): SIMD3(13.35501, -32.35483, -10.34693)
    default: nil
    }
  }
  static func reference(_ pitch: PitchGrip) -> simd_quatd {
    let q: SIMD4<Double> =
      switch pitch {
      case .fourSeam: SIMD4(0.500228, -0.701859, 0.444936, 0.243305)
      case .twoSeam: SIMD4(0.686009, 0.005461, 0.726790, 0.033721)
      case .slider: SIMD4(-0.331717, 0.860799, -0.331717, 0.197366)
      case .circleChange: SIMD4(0.647739, 0.334466, 0.623003, 0.283609)
      }
    return simd_quatd(vector: simd_normalize(q))
  }
  static func samples(_ ball: GripBallAsset, pitch: PitchGrip, finger: GripFinger) -> [Int] {
    guard let anchor = anchor(pitch, finger) else { return Array(ball.seams.indices) }
    return ball.seams.indices.filter { simd_distance(gv(ball.seams[$0].position), anchor) < 9 }
  }
}
