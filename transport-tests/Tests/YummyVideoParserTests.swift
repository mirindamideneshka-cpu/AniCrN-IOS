import XCTest
@testable import TransportChecks

final class YummyVideoParserTests: XCTestCase {
    func testVoicesDeduplicationAndRegionFilter() {
        let rows: [[String: Any]] = [
            ["number": 1, "iframe_url": "//kodik.test/a", "data": ["dubbing": "Voice A", "player": "Kodik"]],
            ["number": "1", "iframe_url": "//kodik.test/a"],
            ["number": "1", "iframe_url": "https://player.test/b", "data": ["dubbing": "Voice B"]],
            ["number": "2", "iframe_url": "https://alloha.test/c"],
            ["number": "3", "iframe_url": "javascript:bad"],
            ["number": "4", "iframe_url": "https://player.test/d", "data": ["player": "Alloha"]]
        ]
        let result = YummyVideoParser.parse(rows, base: URL(string: "https://ru.yummyani.me")!)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.number), ["1", "1"])
        XCTAssertEqual(result[0].voice, "Voice A / Kodik")
        XCTAssertEqual(result[0].url.absoluteString, "https://kodik.test/a")
        XCTAssertNotEqual(result[0].id, result[1].id)
    }
}
