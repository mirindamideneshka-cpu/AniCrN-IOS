import SwiftUI
import SwiftSoup

struct ProviderEntry: Identifiable {
    let id: String
    let title: String
    let url: URL?
}

enum HTMLProviders {
    static func get(_ url: URL, referer: URL, form: [URLQueryItem]? = nil) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 Version/16.0 Mobile Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let form {
            var body = URLComponents()
            body.queryItems = form
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let text = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        return text
    }
    static func absolute(_ raw: String, base: URL) -> URL? {
        guard let url = URL(string: raw, relativeTo: base)?.absoluteURL,
              ["https", "http"].contains(url.scheme ?? "") else { return nil }
        return url
    }
    static func content(_ raw: String) throws -> (String, [String: Any]) {
        guard let data = raw.data(using: .utf8), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any] else { throw URLError(.cannotParseResponse) }
        return (payload["content"] as? String ?? "", payload)
    }
    static func catalog(source: AnimeSource, query: String, page: Int) async throws -> [ProviderEntry] {
        let base = source.site
        var components = URLComponents(url: base, resolvingAgainstBaseURL: true)!
        if source == .animego {
            components.path = query.isEmpty ? "/anime" : "/search/anime"
            components.queryItems = query.isEmpty ? [URLQueryItem(name: "page", value: String(page))] : [URLQueryItem(name: "q", value: query)]
        } else if source == .animevost {
            components.path = query.isEmpty ? (page == 1 ? "/tip/tv/" : "/tip/tv/page/\(page)/") : "/index.php"
            components.queryItems = query.isEmpty ? nil : [URLQueryItem(name: "do", value: "search"), URLQueryItem(name: "subaction", value: "search"), URLQueryItem(name: "story", value: query)]
        } else {
            components.path = query.isEmpty ? (page == 1 ? "/anime/" : "/anime/page/\(page)/") : "/index.php"
            components.queryItems = query.isEmpty ? nil : [URLQueryItem(name: "do", value: "search"), URLQueryItem(name: "subaction", value: "search"), URLQueryItem(name: "story", value: query)]
        }
        let form = source == .animefox && !query.isEmpty ? [URLQueryItem(name: "do", value: "search"), URLQueryItem(name: "subaction", value: "search"), URLQueryItem(name: "story", value: query), URLQueryItem(name: "catlist[]", value: "1")] : nil
        let doc = try SwiftSoup.parse(try await get(components.url!, referer: base, form: form))
        let cards = try doc.select(source == .animego ? ".ani-grid__item, .ani-list__item" : source == .animevost ? "article, .shortstory, .short, .story, .news, .item, .th-item" : "article.short")
        var seen = Set<String>()
        return try cards.array().compactMap { card in
            let selector = source == .animego ? "a[href*=/anime/]" : source == .animevost ? "a[href*=.html]" : "a.short-title[href], a.tc-item[href]"
            guard let link = try card.select(selector).first(), let url = try absolute(link.attr("href"), base: base), seen.insert(url.absoluteString).inserted else { return nil }
            let titleElement = try card.select(source == .animego ? ".ani-grid__item-title, .ani-list__item-title" : source == .animevost ? "h1,h2,h3,.title,.shortstoryHead" : "a.short-title").first()
            let title = try titleElement?.text() ?? link.text()
            return ProviderEntry(id: url.absoluteString, title: title.isEmpty ? url.lastPathComponent : title, url: url)
        }
    }
    static func episodes(_ page: URL) async throws -> [ProviderEntry] {
        let html = try await get(page, referer: AnimeSource.animego.site)
        let doc = try SwiftSoup.parse(html)
        var id = try doc.select("[data-anime]").first()?.attr("data-anime") ?? ""
        if id.isEmpty { id = page.lastPathComponent.components(separatedBy: "-").last ?? "" }
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { throw URLError(.cannotParseResponse) }
        let base = AnimeSource.animego.site
        let (first, payload) = try content(try await get(base.appendingPathComponent("player/" + id), referer: page))
        let player = try SwiftSoup.parse(first)
        let root = try player.select("[data-anime-player-episodes-url-value]").first()
        let total = Int(try root?.attr("data-anime-player-episodes-total-value") ?? "") ?? payload["total"] as? Int ?? 0
        let size = max(1, Int(try root?.attr("data-anime-player-episodes-page-size-value") ?? "") ?? 100)
        var fragments = [first]
        if let raw = try root?.attr("data-anime-player-episodes-url-value"), let url = absolute(raw, base: base) {
            let pages = min(50, max(1, (total + size - 1) / size))
            if pages > 1 {
                for pageIndex in 1..<pages {
                    try Task.checkCancellation()
                    var c = URLComponents(url: url, resolvingAgainstBaseURL: true)!
                    c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "page", value: String(pageIndex))]
                    fragments.append(try content(try await get(c.url!, referer: page)).0)
                }
            }
        }
        var seen = Set<String>()
        return try fragments.flatMap { fragment -> [ProviderEntry] in
            let doc = try SwiftSoup.parse(fragment)
            let modern = try doc.select("[data-episode]").array()
            let legacy = try doc.select("select[name=series] option[value]").array()
            return try (legacy.isEmpty ? modern : legacy).compactMap { item in
                let id = try item.attr(legacy.isEmpty ? "data-episode" : "value")
                guard !id.isEmpty, seen.insert(id).inserted else { return nil }
                let name = try item.attr("data-episode-title")
                let number = try item.attr("data-episode-number")
                return ProviderEntry(id: id, title: name.isEmpty ? (try item.text().isEmpty ? "Серия " + number : item.text()) : name, url: nil)
            }
        }
    }
    static func voices(_ episode: String) async throws -> [ProviderEntry] {
        let base = AnimeSource.animego.site
        let html = try content(try await get(base.appendingPathComponent("player/videos/" + episode), referer: base)).0
        let doc = try SwiftSoup.parse(html)
        var seen = Set<String>()
        return try doc.select("button[data-player]").array().compactMap { button in
            guard let url = try absolute(button.attr("data-player"), base: base), seen.insert(url.absoluteString).inserted else { return nil }
            let label = try button.attr("data-translation-title") + " / " + button.attr("data-provider-title")
            return ProviderEntry(id: url.absoluteString, title: label, url: url)
        }
    }
}

struct HTMLCatalogView: View {
    let source: AnimeSource
    init(source: AnimeSource, initialQuery: String = "") {
        self.source = source
        _query = State(initialValue: initialQuery)
    }
    @State private var query = ""
    @State private var entries: [ProviderEntry] = []
    @State private var page = 1
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(entries) { entry in
                if let url = entry.url {
                    if source == .animego { NavigationLink(entry.title) { AnimeGoEpisodesView(url: url) } }
                    else { NavigationLink(entry.title) { EmbeddedReleaseView(source: source, page: url) } }
                }
            }
            if !loading && entries.isEmpty && error == nil { Text("Ничего не найдено") }
            Button("Следующая страница") { page += 1 }.disabled(loading || !query.isEmpty)
            NavigationLink("Открыть сайт источника") { WebSourceView(initialURL: source.site) }
        }.navigationTitle(source.title).searchable(text: $query)
        .task(id: "\(page):\(query)") {
            loading = true; error = nil
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                let rows = try await HTMLProviders.catalog(source: source, query: query, page: page)
                try Task.checkCancellation(); entries = rows; loading = false
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}

struct AnimeGoEpisodesView: View {
    let url: URL
    @State private var entries: [ProviderEntry] = []
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        List {
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(entries) { entry in NavigationLink(entry.title) { AnimeGoVoicesView(episode: entry.id) } }
            NavigationLink("Плеер на странице") { WebSourceView(initialURL: url) }
        }.navigationTitle("Серии AnimeGo").task {
            do { entries = try await HTMLProviders.episodes(url) } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

struct AnimeGoVoicesView: View {
    let episode: String
    @State private var entries: [ProviderEntry] = []
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        List {
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(entries) { entry in
                if let url = entry.url { NavigationLink(entry.title) { WebSourceView(initialURL: url) } }
            }
            if !loading && entries.isEmpty && error == nil { Text("Нет доступных озвучек") }
        }.navigationTitle("Озвучки AnimeGo").task {
            do { entries = try await HTMLProviders.voices(episode) } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}
