import Foundation
import XCTest

@testable import GripItScannerCore

private let photoResponse = Data(#"{"schemaVersion":"1.0.0","model":"perceptron-mk1.5","requestId":"photo-1","warnings":[],"readings":{"velocityMph":77.3,"totalSpinRpm":1642,"spinDirectionClock":"01:56","spinEfficiencyPercent":93.8,"gyroDegree":null,"horizontalBreakInches":-18.6,"verticalBreakInches":13.8,"releaseHeightFeet":null,"rapsodoScore":null}}"#.utf8)

final class PhotoReadingClientTests: XCTestCase {
  func testSendsImageAndBearerTokenWithStableRequestIdentity() async throws {
    let client = PhotoReadingClient(baseURL: URL(string: "https://gripit.example")!, bearerToken: "session-test") { request in
      XCTAssertEqual(request.url?.absoluteString, "https://gripit.example/api/photos/read")
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-test")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "photo-1")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/png")
      XCTAssertEqual(request.httpBody, Data([1, 2, 3]))
      XCTAssertGreaterThan(request.timeoutInterval, 30)
      return (photoResponse, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    let response = try await client.read(image: Data([1, 2, 3]), contentType: "image/png", requestId: "photo-1")
    let row = response.makeDraft(source: .sample)
    XCTAssertEqual(row.velocityMph, "77.3")
    XCTAssertEqual(row.totalSpinRpm, "1642")
    XCTAssertEqual(row.spinDirectionClock, "01:56")
    XCTAssertEqual(row.spinEfficiencyPercent, "93.8")
    XCTAssertEqual(row.horizontalBreakInches, "-18.6")
    XCTAssertTrue(row.gyroDegree.isEmpty)
    XCTAssertTrue(row.releaseHeightFeet.isEmpty)
    XCTAssertTrue(row.rapsodoScore.isEmpty)
    XCTAssertTrue(row.id.hasPrefix("sample-"))
    XCTAssertFalse(response.makeDraft(source: .manual).id.hasPrefix("sample-"))
  }

  func testMissingOptionalKeysAreNotSilentlyAcceptedAsNull() async throws {
    let malformed = photoResponse.replacing("\"gyroDegree\":null,", with: "")
    await assertError(.invalidResponse, status: 200, data: malformed)
  }

  func testRejectsUnsupportedSchemaModelWrongRequestAndMalformedJSON() async throws {
    for data in [
      photoResponse.replacing("1.0.0", with: "2.0.0"),
      photoResponse.replacing("perceptron-mk1.5", with: "other-model"),
      photoResponse.replacing("photo-1", with: "other-request"),
      Data("not json".utf8),
    ] { await assertError(.invalidResponse, status: 200, data: data) }
  }

  func testMapsAccountAndProviderFailuresWithoutShowingRawServerErrors() async throws {
    let raw = Data(#"{"error":{"code":"quota_exceeded","message":"secret internal detail"}}"#.utf8)
    await assertError(.signInRequired, status: 401, data: raw)
    await assertError(.quotaExceeded, status: 429, data: raw)
    await assertError(.unavailable, status: 429, data: Data(#"{"error":{"code":"rate_limited"}}"#.utf8))
    await assertError(.timedOut, status: 504, data: raw)
    await assertError(.unreadable, status: 502, data: raw)
    await assertError(.unavailable, status: 503, data: raw)
    XCTAssertFalse(PhotoReadingError.quotaExceeded.localizedDescription.contains("secret"))
  }

  func testDoesNotStartRequestWhenCancelled() async throws {
    let client = PhotoReadingClient(baseURL: URL(string: "https://gripit.example")!) { _ in
      XCTFail("Cancelled requests must not reach the network")
      throw URLError(.badServerResponse)
    }
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await client.read(image: Data([1]), contentType: "image/png", requestId: "photo-1")
    }
    do { _ = try await task.value; XCTFail("Expected cancellation") }
    catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
  }

  func testPropagatesCancellationAndMapsNetworkTimeout() async throws {
    for code in [URLError.cancelled, .timedOut, .notConnectedToInternet] {
      let client = PhotoReadingClient(baseURL: URL(string: "https://gripit.example")!) { _ in throw URLError(code) }
      do {
        _ = try await client.read(image: Data([1]), contentType: "image/png", requestId: "photo-1")
        XCTFail("Expected error")
      } catch is CancellationError { XCTAssertEqual(code, .cancelled) }
      catch let error as PhotoReadingError { XCTAssertEqual(error, code == .timedOut ? .timedOut : .unavailable) }
    }
  }

  func testRejectsEmptyOversizedOrUnsupportedUploadsBeforeNetwork() async throws {
    let client = PhotoReadingClient(baseURL: URL(string: "https://gripit.example")!) { _ in
      XCTFail("Invalid images must not reach the network")
      throw URLError(.badServerResponse)
    }
    for (image, type) in [(Data(), "image/png"), (Data(repeating: 1, count: 4 * 1024 * 1024 + 1), "image/png"), (Data([1]), "image/webp")] {
      do { _ = try await client.read(image: image, contentType: type, requestId: "photo-1"); XCTFail("Expected error") }
      catch let error as PhotoReadingError { XCTAssertEqual(error, .invalidPhoto) }
    }
  }

  func testCancelledTaskCannotPublishALateSuccessfulResponse() async throws {
    let client = PhotoReadingClient(baseURL: URL(string: "https://gripit.example")!) { request in
      withUnsafeCurrentTask { $0?.cancel() }
      return (photoResponse, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    let task = Task {
      try await client.read(image: Data([1]), contentType: "image/png", requestId: "photo-1")
    }
    do { _ = try await task.value; XCTFail("A cancelled task must not publish a result") }
    catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
  }

  private func assertError(_ expected: PhotoReadingError, status: Int, data: Data) async {
    let client = PhotoReadingClient(baseURL: URL(string: "https://gripit.example")!) { request in
      (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    do { _ = try await client.read(image: Data([1]), contentType: "image/png", requestId: "photo-1"); XCTFail("Expected error") }
    catch let error as PhotoReadingError { XCTAssertEqual(error, expected) }
    catch { XCTFail("Unexpected error: \(error)") }
  }
}

private extension Data {
  func replacing(_ target: String, with replacement: String) -> Data {
    Data(String(decoding: self, as: UTF8.self).replacingOccurrences(of: target, with: replacement).utf8)
  }
}
