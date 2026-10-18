import XCTest

@testable import GripItScannerCore

private actor LoadCounter {
  var count = 0
  func next() -> Int {
    count += 1
    return count
  }
}

final class SessionTaskCacheTests: XCTestCase {
  func testConcurrentLoadsAndRevisitsReuseWork() async throws {
    let cache = SessionTaskCache<String, Int>()
    let counter = LoadCounter()
    let load: @Sendable () async throws -> Int = {
      let value = await counter.next()
      try await Task.sleep(for: .milliseconds(30))
      return value
    }
    async let first = cache.value(for: "four-seam", load: load)
    async let second = cache.value(for: "four-seam", load: load)
    let both = try await [first, second]
    XCTAssertEqual(both, [1, 1])
    let again = try await cache.value(for: "four-seam", load: load)
    XCTAssertEqual(again, 1)
    let other = try await cache.value(for: "slider", load: load)
    XCTAssertEqual(other, 2)
  }

  func testFailuresCanRetryAndAnotherHandHasSeparateCache() async throws {
    let cache = SessionTaskCache<String, Int>()
    let counter = LoadCounter()
    let load: @Sendable () async throws -> Int = {
      let n = await counter.next()
      if n == 1 { throw URLError(.cannotDecodeRawData) }
      return n
    }
    do {
      _ = try await cache.value(for: "pitch", load: load)
      XCTFail("Expected the first load to fail")
    } catch {}
    let retry = try await cache.value(for: "pitch", load: load)
    XCTAssertEqual(retry, 2)
    let newHandCache = SessionTaskCache<String, Int>()
    let separate = try await newHandCache.value(for: "pitch", load: load)
    XCTAssertEqual(separate, 3)
  }
}
