import XCTest
import simd
@testable import GripItScannerCore

final class GripRaisedBallTests: XCTestCase {
  func testOriginalBallThreadsHaveUniformRadiusAndOutwardFaces() throws {
    let ball = try GripBallAsset.load()
    let threads = try GripBallStitchAsset.load()
    XCTAssertEqual(threads.sourceSHA256, ball.sourceSHA256)
    XCTAssertGreaterThan(threads.stitchCount, 200)
    XCTAssertEqual(threads.vertices.count, threads.normals.count)
    var peak = 0.0
    for i in threads.vertices.indices {
      let p = gv(threads.vertices[i]), n = gv(threads.normals[i])
      XCTAssertEqual(simd_length(n), 1, accuracy: 0.00001)
      let radius = simd_length(p)
      XCTAssertGreaterThanOrEqual(radius, 36.42)
      XCTAssertLessThanOrEqual(radius, 37.08)
      peak = max(peak, radius)
      // Ring vertices are exactly 0.32 mm from their surface-following center;
      // end-cap centers differ by less than 0.002 mm in this radial check.
      XCTAssertEqual(simd_length(p - n * threads.threadRadiusMm),
        threads.threadCenterRadiusMm, accuracy: 0.002)
    }
    XCTAssertEqual(peak - GripPoseSolver.ballRadius, 0.57, accuracy: 0.00001)
    for i in stride(from: 0, to: threads.indices.count, by: 3) {
      let ids = (0..<3).map { Int(threads.indices[i+$0]) }
      let p = ids.map { gv(threads.vertices[$0]) }
      let n = ids.reduce(SIMD3<Double>.zero) { $0 + gv(threads.normals[$1]) }
      XCTAssertGreaterThan(simd_dot(simd_cross(p[1]-p[0],p[2]-p[0]), n), 0,
        "Thread faces must remain visible from outside the ball")
    }
  }
}
