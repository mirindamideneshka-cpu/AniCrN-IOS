import XCTest
#if canImport(TransportChecks)
@testable import TransportChecks
#endif

final class MediaRouteCodecTests: XCTestCase {
    func testSignedURLRoundTripAndSessionIsolation() throws {
        let codec = MediaRouteCodec()
        let url = URL(string: "https://cdn.test/segment.ts?sig=a%2Fb&time=12")!
        let path = try codec.encode(url)
        XCTAssertFalse(path.contains("sig="))
        XCTAssertEqual(codec.decode(path), url)
        XCTAssertNil(MediaRouteCodec().decode(path))
        XCTAssertNil(codec.decode(path.replacingOccurrences(of: ".ts", with: "x.ts")))
    }
}
