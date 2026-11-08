import SwiftUI

enum AnimeSource: String, CaseIterable, Identifiable {
    case aniliberty, animego, animefox, shikimori, animelib, yummyanime, animevost
    var id: String { rawValue }
    var title: String {
        switch self {
        case .aniliberty: return "AniLiberty"
        case .animego: return "AnimeGo"
        case .animefox: return "AnimeFox"
        case .shikimori: return "Shikimori · метаданные"
        case .animelib: return "AnimeLib"
        case .yummyanime: return "YummyAnime"
        case .animevost: return "AnimeVost · дополнительный"
        }
    }
    var site: URL {
        let address: String
        switch self {
        case .aniliberty: address = "https://anilibria.top"
        case .animego: address = "https://animego.me"
        case .animefox: address = "https://www.animefox.org/anime/"
        case .shikimori: address = "https://shikimori.one"
        case .animelib: address = "https://v5.animelib.org/ru"
        case .yummyanime: address = "https://ru.yummyani.me"
        case .animevost: address = "https://animevost.org"
        }
        return URL(string: address)!
    }
}

struct SourcesView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Нативный API") {
                    NavigationLink("AniLiberty · каталог и серии") { CatalogView() }
                    NavigationLink("AnimeLib · каталог и серии") { AnimeLibCatalogView() }
                    NavigationLink("AnimeGo · каталог и серии") { HTMLCatalogView(source: .animego) }
                    NavigationLink("AnimeFox · каталог") { HTMLCatalogView(source: .animefox) }
                    NavigationLink("Shikimori · каталог метаданных") { ShikimoriCatalogView() }
                }
                Section("Веб-источники · поиск и выбор на сайте") {
                    ForEach(AnimeSource.allCases) { source in
                        NavigationLink(source.title) { WebSourceView(initialURL: source.site) }
                    }
                }
            }.navigationTitle("Источники")
        }
    }
}

struct ShikimoriCatalogView: View {
    @State private var query = ""
    @State private var entries: [Anime] = []
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        List {
            Text("Shikimori предоставляет метаданные. Для просмотра выберите релиз в источнике с видео.").font(.caption)
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(entries) { anime in
                NavigationLink(anime.title) {
                    List {
                        Text(anime.description)
                        NavigationLink("Найти в AnimeGo") { HTMLCatalogView(source: .animego, initialQuery: anime.title) }
                        NavigationLink("Найти в AnimeFox") { HTMLCatalogView(source: .animefox, initialQuery: anime.title) }
                    }.navigationTitle(anime.title)
                }
            }
        }.navigationTitle("Shikimori").searchable(text: $query).task(id: query) {
            loading = true; error = nil
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                var c = URLComponents(string: "https://shikimori.one/api/animes")!
                c.queryItems = [URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "order", value: "popularity")]
                if !query.isEmpty { c.queryItems?.append(URLQueryItem(name: "search", value: query)) }
                let rows = try await ProviderNetwork.json(c.url!, site: AnimeSource.shikimori.site) as? [[String: Any]] ?? []
                try Task.checkCancellation()
                entries = rows.compactMap { row in
                    guard let id = row["id"] as? NSNumber else { return nil }
                    let russian = row["russian"] as? String ?? ""
                    return Anime(id: id.stringValue, title: russian.isEmpty ? row["name"] as? String ?? id.stringValue : russian, description: row["name"] as? String ?? "", poster: "")
                }
                loading = false
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}

enum ProviderNetwork {
    static func json(_ url: URL, site: URL) async throws -> Any {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue(site.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("https://" + (site.host ?? ""), forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AniCrN-iOS/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONSerialization.jsonObject(with: data)
    }
}

enum AnimeLibAPI {
    static let base = "https://hapi.hentaicdn.org/api"
    static func request(_ path: String, query: [URLQueryItem] = []) async throws -> [String: Any] {
        var components = URLComponents(string: base + path)!
        components.queryItems = query.isEmpty ? nil : query
        guard let root = try await ProviderNetwork.json(components.url!, site: AnimeSource.animelib.site) as? [String: Any] else { throw URLError(.cannotParseResponse) }
        return root
    }
}

struct AnimeLibCatalogView: View {
    @State private var query = ""
    @State private var titles: [Anime] = []
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        List {
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(titles) { anime in
                NavigationLink(anime.title) { AnimeLibEpisodesView(anime: anime) }
            }
        }.navigationTitle("AnimeLib").searchable(text: $query)
        .task(id: query) {
            loading = true; error = nil
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                var params = [URLQueryItem(name: "site_id[]", value: "5"), URLQueryItem(name: "page", value: "1")]
                if !query.isEmpty { params.append(URLQueryItem(name: "q", value: query)) }
                else { params += [URLQueryItem(name: "sort_by", value: "rating_score"), URLQueryItem(name: "sort_type", value: "desc")] }
                let root = try await AnimeLibAPI.request("/anime", query: params)
                try Task.checkCancellation()
                titles = (root["data"] as? [[String: Any]] ?? []).compactMap { item in
                    guard let id = item["slug_url"] as? String else { return nil }
                    let cover = item["cover"] as? [String: Any]
                    return Anime(id: id, title: item["rus_name"] as? String ?? item["name"] as? String ?? id,
                                 description: item["summary"] as? String ?? "", poster: cover?["md"] as? String ?? "")
                }
                loading = false
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}

struct AnimeLibEpisodesView: View {
    let anime: Anime
    @State private var episodes: [LibEpisode] = []
    @State private var error: String?
    @State private var loading = true
    struct LibEpisode: Identifiable { let id: String; let title: String }
    var body: some View {
        List {
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(episodes) { episode in
                NavigationLink(episode.title) { AnimeLibPlayersView(episodeID: episode.id) }
            }
        }.navigationTitle(anime.title).task {
            do {
                let id = anime.id.components(separatedBy: "--")[0].filter(\.isNumber)
                let root = try await AnimeLibAPI.request("/episodes", query: [URLQueryItem(name: "anime_id", value: id)])
                episodes = (root["data"] as? [[String: Any]] ?? []).compactMap { item in
                    guard let id = item["id"] as? NSNumber else { return nil }
                    return LibEpisode(id: id.stringValue, title: "Серия \(item["number"] ?? "") · \(item["name"] ?? "")")
                }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

struct AnimeLibPlayersView: View {
    let episodeID: String
    @State private var players: [LibPlayer] = []
    @State private var error: String?
    @State private var loading = true
    struct LibPlayer: Identifiable { let id: String; let title: String; let url: URL }
    var body: some View {
        List {
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            if !loading && players.isEmpty && error == nil { Text("Доступных плееров нет") }
            ForEach(players) { player in
                if ["m3u8", "mp4"].contains(player.url.pathExtension.lowercased()) {
                    NavigationLink(player.title) { PlaybackView(url: player.url) }
                } else {
                    NavigationLink(player.title) { WebSourceView(initialURL: player.url) }
                }
            }
        }.navigationTitle("Озвучки").task {
            do {
                let root = try await AnimeLibAPI.request("/episodes/" + episodeID)
                let data = root["data"] as? [String: Any]
                players = (data?["players"] as? [[String: Any]] ?? []).compactMap { item in
                    guard let id = item["id"] as? NSNumber, let raw = item["src"] as? String,
                          let url = URL(string: raw.hasPrefix("//") ? "https:" + raw : raw),
                          ["https", "http"].contains(url.scheme ?? "") else { return nil }
                    let team = item["team"] as? [String: Any]
                    let translation = item["translation_type"] as? [String: Any]
                    return LibPlayer(id: id.stringValue, title: [team?["name"] as? String, translation?["label"] as? String, item["player"] as? String].compactMap { $0 }.joined(separator: " · "), url: url)
                }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}
