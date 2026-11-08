import XCTest
@testable import TransportChecks

final class HLSPlaylistTests: XCTestCase {
    func testNestedPlaylistSegmentKeyAndMap() {
        let input = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"../key.bin?t=1&x=2\"\n#EXT-X-MAP:URI=\"init.mp4\"\nvariant/main.m3u8\npart.ts\n"
        var seen: [String] = []
        let result = HLSPlaylist.rewrite(input, base: URL(string: "https://cdn.test/path/master.m3u8")!) { url in
            seen.append(url.absoluteString)
            return URL(string: "http://127.0.0.1/route\(seen.count)")!
        }
        XCTAssertEqual(seen, ["https://cdn.test/key.bin?t=1&x=2", "https://cdn.test/path/init.mp4", "https://cdn.test/path/variant/main.m3u8", "https://cdn.test/path/part.ts"])
        XCTAssertFalse(result.contains("https://cdn.test"))
        XCTAssertTrue(result.contains("#EXT-X-KEY:METHOD=AES-128,URI=\"http://127.0.0.1/route1\""))
    }
    func testKeepsNonHTTPKeyAndSignedQuery() {
        let input = "#EXTM3U\r\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"skd://key\"\r\n//other.test/a.ts?sig=a%2Fb&time=12\r\n"
        var seen: [URL] = []
        let output = HLSPlaylist.rewrite(input, base: URL(string: "https://cdn.test/a.m3u8")!) { seen.append($0); return $0 }
        XCTAssertEqual(seen.map(\.absoluteString), ["https://other.test/a.ts?sig=a%2Fb&time=12"])
        XCTAssertTrue(output.contains("skd://key"))
    }
}
