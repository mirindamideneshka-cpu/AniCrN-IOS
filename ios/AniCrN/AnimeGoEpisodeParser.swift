import Foundation
import SwiftSoup

struct ParsedEpisode: Equatable {
    let id: String
    let title: String
}
enum AnimeGoEpisodeParser {
    static func parse(_ fragments: [String]) throws -> [ParsedEpisode] {
        var seen = Set<String>()
        return try fragments.flatMap { fragment -> [ParsedEpisode] in
            let doc = try SwiftSoup.parse(fragment)
            let modern = try doc.select("[data-anime-player-episodes-target=episode][data-episode], .player-video-bar__item[data-episode]").array()
            let legacy = try doc.select("select[name=series] option[value]").array()
            return try (legacy.isEmpty ? modern : legacy).compactMap { item in
                let id = try item.attr(legacy.isEmpty ? "data-episode" : "value")
                guard !id.isEmpty, seen.insert(id).inserted else { return nil }
                let modernItem = try modern.first { try $0.attr("data-episode") == id }
                let title = try (modernItem ?? item).attr("data-episode-title")
                let number = try (modernItem ?? item).attr("data-episode-number")
                let text = try item.text()
                return ParsedEpisode(id: id, title: !title.isEmpty ? title : !text.isEmpty ? text : "Серия " + number)
            }
        }
    }
}
