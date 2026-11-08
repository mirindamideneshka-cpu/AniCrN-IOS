import XCTest
@testable import TransportChecks

final class HostStreamParserTests: XCTestCase {
    func testAniBoomNestedJSONParameters() throws {
        let html = #"<video data-parameters='{"hls":"{\"src\":\"https://cdn.test/a.m3u8?x=1&amp;y=2\"}"}'></video>"#
        let result = try HostStreamParser.parse(html, page: URL(string: "https://aniboom.one/embed/1")!)
        XCTAssertEqual(result.map(\.absoluteString), ["https://cdn.test/a.m3u8?x=1&y=2"])
    }
    func testSibnetRelativeMP4AndHostScope() throws {
        let html = #"player.src({src: "/v/a.mp4?sig=abc", type:"video/mp4"});"#
        XCTAssertEqual(try HostStreamParser.parse(html, page: URL(string: "https://video.sibnet.ru/shell.php?id=1")!).first?.absoluteString, "https://video.sibnet.ru/v/a.mp4?sig=abc")
        XCTAssertTrue(try HostStreamParser.parse(html, page: URL(string: "https://unrelated.test/")!).isEmpty)
    }
}
