import XCTest
#if canImport(TransportChecks)
@testable import TransportChecks
#endif

final class ProviderHTTPTests: XCTestCase {
    func testOnlyTemporaryGETFailuresRetry() {
        XCTAssertTrue(ProviderHTTP.canRetry(method: "GET", status: 503, error: nil))
        XCTAssertTrue(ProviderHTTP.canRetry(method: nil, status: nil, error: URLError(.timedOut)))
        XCTAssertFalse(ProviderHTTP.canRetry(method: "POST", status: 503, error: nil))
        XCTAssertFalse(ProviderHTTP.canRetry(method: "GET", status: 403, error: nil))
        XCTAssertFalse(ProviderHTTP.canRetry(method: "GET", status: nil, error: URLError(.cancelled)))
    }
}
