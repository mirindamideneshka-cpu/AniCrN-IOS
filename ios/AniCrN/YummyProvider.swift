import SwiftUI
import SwiftSoup

enum YummyAPI {
    static func webSearch(_ query: String) async throws -> Anime? {
        let slug = YummySlug.make(query)
        guard !slug.isEmpty else { return nil }
        let url = AnimeSource.yummyanime.site.appendingPathComponent("catalog/item/" + slug)
        let html = try await HTMLProviders.get(url, referer: AnimeSource.yummyanime.site)
        let doc = try SwiftSoup.parse(html)
        let title = try doc.select("h1").first()?.text() ?? doc.select("meta[property=og:title]").first()?.attr("content") ?? ""
        guard !title.isEmpty else { return nil }
        let description = try doc.select("meta[name=description]").first()?.attr("content") ?? ""
        let poster = try doc.select("meta[property=og:image]").first()?.attr("content") ?? ""
        return Anime(id: slug, title: title, description: description, poster: poster)
    }
    static func request(_ path: String, query: [URLQueryItem] = []) async throws -> Any {
        var lastError: Error = URLError(.cannotConnectToHost)
        for base in ["https://api.yani.tv", "https://ru.yummyani.me/api"] {
            do {
                var c = URLComponents(string: base + path)!
                c.queryItems = query.isEmpty ? nil : query
                guard let root = try await ProviderNetwork.json(c.url!, site: AnimeSource.yummyanime.site) as? [String: Any], let response = root["response"] else { throw URLError(.cannotParseResponse) }
                return response
            } catch { if Task.isCancelled { throw CancellationError() }; lastError = error }
        }
        throw lastError
    }
    static func title(_ row: [String: Any]) -> Anime? {
        let id = ["anime_url", "url", "alias", "slug", "id", "anime_id"].compactMap { key -> String? in
            if let value = row[key] as? String, !value.isEmpty { return value }
            return (row[key] as? NSNumber)?.stringValue
        }.first
        guard let id else { return nil }
        let normalized = id.components(separatedBy: "/catalog/item/").last?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? id
        let image = row["poster"] as? [String: Any]
        let raw = image?["big"] as? String ?? image?["medium"] as? String ?? row["poster_url"] as? String ?? ""
        let poster = raw.isEmpty ? "" : HTMLProviders.absolute(raw, base: AnimeSource.yummyanime.site)?.absoluteString ?? ""
        return Anime(id: normalized, title: row["title"] as? String ?? normalized, description: row["description"] as? String ?? "", poster: poster)
    }
}

struct YummyCatalogView: View {
    @State private var query = ""
    @State private var titles: [Anime] = []
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        List {
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(titles) { anime in NavigationLink(anime.title) { YummyEpisodesView(anime: anime) } }
            NavigationLink("Сайт YummyAnime") { WebSourceView(initialURL: AnimeSource.yummyanime.site) }
        }.navigationTitle("YummyAnime").searchable(text: $query).task(id: query) {
            loading = true; error = nil
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                var rows: [[String: Any]]
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let feed = try await YummyAPI.request("/feed") as? [String: Any]
                    rows = feed?["new_videos"] as? [[String: Any]] ?? []
                } else {
                    do {
                        rows = try await YummyAPI.request("/search", query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "offset", value: "0")]) as? [[String: Any]] ?? []
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                        guard let fallback = try await YummyAPI.webSearch(query) else { throw error }
                        try Task.checkCancellation()
                        titles = [fallback]; loading = false; return
                    }
                }
                try Task.checkCancellation()
                var seen = Set<String>()
                titles = rows.compactMap(YummyAPI.title).filter { seen.insert($0.id).inserted }
                if !query.isEmpty && !titles.contains(where: { $0.title.localizedCaseInsensitiveContains(query) }) {
                    do {
                        if let fallback = try await YummyAPI.webSearch(query), seen.insert(fallback.id).inserted {
                            try Task.checkCancellation(); titles.append(fallback)
                        }
                    } catch { if Task.isCancelled { throw CancellationError() } }
                }
                loading = false
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}

struct YummyEpisodesView: View {
    let anime: Anime
    @State private var videos: [YummyVideo] = []
    @State private var error: String?
    @State private var loading = true
    private var numbers: [String] {
        Array(Set(videos.map(\.number))).sorted { ($0.replacingOccurrences(of: ",", with: ".") as NSString).doubleValue < ($1.replacingOccurrences(of: ",", with: ".") as NSString).doubleValue }
    }
    var body: some View {
        List {
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(numbers, id: \.self) { number in
                Section("Серия " + number) {
                    ForEach(videos.filter { $0.number == number }) { video in
                        NavigationLink(video.voice) {
                            if ["mp4", "m3u8"].contains(video.url.pathExtension.lowercased()) { PlaybackView(url: video.url, headers: ["Referer": AnimeSource.yummyanime.site.absoluteString, "Origin": AnimeSource.yummyanime.site.absoluteString]) }
                            else { WebSourceView(initialURL: video.url, referer: AnimeSource.yummyanime.site) }
                        }
                    }
                }
            }
            if !loading && videos.isEmpty && error == nil { Text("Доступных серий нет") }
        }.navigationTitle(anime.title).task {
            do {
                let id = anime.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? anime.id
                let row = try await YummyAPI.request("/anime/" + id, query: [URLQueryItem(name: "need_videos", value: "1")]) as? [String: Any]
                videos = YummyVideoParser.parse(row?["videos"] as? [[String: Any]] ?? [], base: AnimeSource.yummyanime.site)
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}
