import XCTest
@testable import TransportChecks

final class ProviderHTMLParserTests: XCTestCase {
    func testAnimeGoModernGridAndListDeduplication() throws {
        let html = #"<div class="ani-grid__item"><a href="/anime/test-123"><img></a><div class="ani-grid__item-title"><a href="/anime/test-123">Тест &amp; мир</a></div></div><div class="ani-list__item"><div class="ani-list__item-title"><a href="/anime/test-123">Повтор</a></div></div>"#
        let rows = try ProviderHTMLParser.cards(html, source: "animego", base: URL(string: "https://animego.me/anime?page=2")!)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.title, "Тест & мир")
        XCTAssertEqual(rows.first?.url.absoluteString, "https://animego.me/anime/test-123")
    }
    func testFoxAndVostRelativeLinks() throws {
        let fox = #"<article class="short"><a class="short-title" href="/anime/10-test.html"><h2>Тест</h2></a></article>"#
        XCTAssertEqual(try ProviderHTMLParser.cards(fox, source: "animefox", base: URL(string: "https://www.animefox.org/anime/")!).first?.title, "Тест")
        let vost = #"<div class="shortstory"><h2>Сериал</h2><a href="/tip/tv/1.html">Подробнее</a></div>"#
        XCTAssertEqual(try ProviderHTMLParser.cards(vost, source: "animevost", base: URL(string: "https://animevost.org/tip/tv/")!).first?.url.host, "animevost.org")
    }
}
