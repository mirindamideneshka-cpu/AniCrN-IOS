import Foundation
import SwiftSoup

struct HTMLTitle: Equatable {
    let title: String
    let url: URL
}
enum ProviderHTMLParser {
    static func cards(_ html: String, source: String, base: URL) throws -> [HTMLTitle] {
        let doc = try SwiftSoup.parse(html)
        let cardSelector = source == "animego" ? ".ani-grid__item, .ani-list__item" : source == "animevost" ? "article, .shortstory, .short, .story, .news, .item, .th-item" : "article.short"
        let linkSelector = source == "animego" ? "a[href*=/anime/]" : source == "animevost" ? "a[href*=.html]" : "a.short-title[href], a.tc-item[href]"
        let titleSelector = source == "animego" ? ".ani-grid__item-title, .ani-list__item-title" : source == "animevost" ? "h1,h2,h3,.title,.shortstoryHead" : "a.short-title"
        var seen = Set<URL>()
        return try doc.select(cardSelector).array().compactMap { card in
            guard let link = try card.select(linkSelector).first(),
                  let url = try URL(string: link.attr("href"), relativeTo: base)?.absoluteURL,
                  ["https", "http"].contains(url.scheme ?? ""), seen.insert(url).inserted else { return nil }
            let element = try card.select(titleSelector).first()
            let title = try element?.text() ?? link.text()
            return HTMLTitle(title: title.isEmpty ? url.lastPathComponent : title, url: url)
        }
    }
}
