import XCTest
import simd

@testable import GripItScannerCore

/// The viewer used to rebuild the zone surface and the shading weights on the
/// main thread every time the pitch changed. These assert that moving that work
/// into a prebuilt value produces byte-identical data, so the saving is purely
/// when the work happens rather than what it produces.
final class GripRenderStateTests: XCTestCase {
  func testPrebuiltStateMatchesWhatTheViewUsedToComputeInline() throws {
    let profile = try SampleHandProfiles.averageRight()
    let hand = try GripHandAsset.load()
    for pitch in PitchGrip.allCases {
      let pose = try GripPoseSolver.solve(profile: profile, pitch: pitch)
      let state = try GripRenderState(pose: pose)

      let plan = GripPlan(pose: pose)
      let surface = GripZoneSurface(pose: pose, gripPlan: plan, hand: hand)
      let shading = GripPoseSolver.pressureShadingWeights(hand: hand, pose: pose)

      XCTAssertEqual(state.pose.id, pose.id, "\(pitch) must keep the solved pose")
      XCTAssertEqual(
        state.plan.zones.map(\.zoneId), plan.zones.map(\.zoneId), "\(pitch) zones")
      XCTAssertEqual(
        state.plan.zones.map(\.reach), plan.zones.map(\.reach), "\(pitch) reach")
      XCTAssertEqual(state.surface.weights.count, surface.weights.count, "\(pitch) surface size")
      XCTAssertEqual(state.surface.weights, surface.weights, "\(pitch) surface weights")
      // Shading diffuses over per-vertex neighbour `Set`s, and a Set does not
      // promise an iteration order, so summing the same neighbours twice can
      // land an ULP apart. Compare within tolerance rather than bit-for-bit.
      XCTAssertEqual(state.pressureWeights.count, shading.count, "\(pitch) shading size")
      for (prebuilt, inline) in zip(state.pressureWeights, shading) {
        XCTAssertEqual(prebuilt, inline, accuracy: 1e-12, "\(pitch) shading weights")
      }
    }
  }

  func testStateCoversEveryMeshVertexSoColouringNeedsNoFallback() throws {
    let profile = try SampleHandProfiles.averageRight()
    let pose = try GripPoseSolver.solve(profile: profile, pitch: .fourSeam)
    let state = try GripRenderState(pose: pose)
    XCTAssertEqual(state.surface.weights.count, pose.vertices.count)
    XCTAssertEqual(state.pressureWeights.count, pose.vertices.count)
    XCTAssertTrue(state.pressureWeights.allSatisfy(\.isFinite))
  }

  /// Switching pitch and switching back must not redo the expensive derivation.
  func testStudioCacheReusesOneRenderStatePerPitch() async throws {
    let profile = try SampleHandProfiles.averageRight()
    let cache = SessionTaskCache<PitchGrip, GripRenderState>()
    let build: @Sendable (PitchGrip) async -> GripRenderState = { pitch in
      try! GripRenderState(pose: try! GripPoseSolver.solve(profile: profile, pitch: pitch))
    }
    let first = try await cache.value(for: .fourSeam) { await build(.fourSeam) }
    _ = try await cache.value(for: .slider) { await build(.slider) }
    let revisited = try await cache.value(for: .fourSeam) { await build(.fourSeam) }
    XCTAssertEqual(first.pose.id, revisited.pose.id, "revisiting a pitch must reuse the same pose")
  }
}
