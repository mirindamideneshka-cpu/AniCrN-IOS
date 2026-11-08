import SwiftUI

enum YummyAPI {
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
        return Anime(id: normalized, title: row["title"] as? String ?? normalized, description: row["description"] as? String ?? "", poster: "")
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
                let rows: [[String: Any]]
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let feed = try await YummyAPI.request("/feed") as? [String: Any]
                    rows = feed?["new_videos"] as? [[String: Any]] ?? []
                } else {
                    rows = try await YummyAPI.request("/search", query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "offset", value: "0")]) as? [[String: Any]] ?? []
                }
                try Task.checkCancellation()
                var seen = Set<String>()
                titles = rows.compactMap(YummyAPI.title).filter { seen.insert($0.id).inserted }
                loading = false
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}

struct YummyEpisodesView: View {
    let anime: Anime
    struct Video: Identifiable {
        let id: String
        let number: String
        let voice: String
        let url: URL
    }
    @State private var videos: [Video] = []
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
                            if ["mp4", "m3u8"].contains(video.url.pathExtension.lowercased()) { PlaybackView(url: video.url) }
                            else { WebSourceView(initialURL: video.url) }
                        }
                    }
                }
            }
            if !loading && videos.isEmpty && error == nil { Text("Доступных серий нет") }
        }.navigationTitle(anime.title).task {
            do {
                let id = anime.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? anime.id
                let row = try await YummyAPI.request("/anime/" + id, query: [URLQueryItem(name: "need_videos", value: "1")]) as? [String: Any]
                var seen = Set<String>()
                videos = (row?["videos"] as? [[String: Any]] ?? []).compactMap { item in
                    let number = (item["number"] as? String) ?? (item["number"] as? NSNumber)?.stringValue ?? ""
                    guard !number.isEmpty, let raw = item["iframe_url"] as? String,
                          let url = HTMLProviders.absolute(raw, base: AnimeSource.yummyanime.site) else { return nil }
                    let key = number + "|" + url.absoluteString
                    guard seen.insert(key).inserted else { return nil }
                    let data = item["data"] as? [String: Any]
                    let voice = [data?["dubbing"] as? String, data?["player"] as? String].compactMap { $0 }.joined(separator: " / ")
                    return Video(id: key, number: number, voice: voice.isEmpty ? "Плеер" : voice, url: url)
                }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}
