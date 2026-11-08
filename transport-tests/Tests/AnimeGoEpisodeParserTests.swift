import XCTest
@testable import TransportChecks

final class AnimeGoEpisodeParserTests: XCTestCase {
    func testModernPaginationDeduplication() throws {
        let page1 = #"<div data-anime-player-episodes-target="episode" data-episode="a" data-episode-number="1" data-episode-title="Начало"></div><span data-episode="advert">Ad</span>"#
        let page2 = #"<div class="player-video-bar__item" data-episode="a"></div><div class="player-video-bar__item" data-episode="b" data-episode-number="2"></div>"#
        XCTAssertEqual(try AnimeGoEpisodeParser.parse([page1, page2]), [ParsedEpisode(id: "a", title: "Начало"), ParsedEpisode(id: "b", title: "Серия 2")])
    }
    func testLegacyOptionsUseModernMetadata() throws {
        let html = #"<select name="series"><option value="x">1 серия</option></select><div class="player-video-bar__item" data-episode="x" data-episode-title="Название"></div>"#
        XCTAssertEqual(try AnimeGoEpisodeParser.parse([html]), [ParsedEpisode(id: "x", title: "Название")])
    }
}
