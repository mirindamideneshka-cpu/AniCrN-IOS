import SwiftUI
import AVKit

struct Anime: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let poster: String
}

enum Provider {
    static func request(_ path: String) async throws -> Data {
        guard let url = URL(string: "https://anilibria.top/api/v1" + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    static func catalog(query: String) async throws -> [Anime] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if query.isEmpty { path = "/anime/catalog/releases?page=1&limit=40" }
        else {
            var parts = URLComponents()
            parts.queryItems = [URLQueryItem(name: "query", value: query)]
            path = "/app/search/releases?" + (parts.percentEncodedQuery ?? "")
        }
        let data = try await request(path)
        guard let input = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
        return try input.withCString { input in
            guard let output = anicrn_normalize(input) else { throw URLError(.cannotParseResponse) }
            defer { anicrn_free(output) }
            return try JSONDecoder().decode([Anime].self, from: Data(String(cString: output).utf8))
        }
    }
}

@main
struct AniCrNApp: App {
    var body: some Scene { WindowGroup { SourcesView().preferredColorScheme(.dark) } }
}

struct CatalogView: View {
    @State private var titles: [Anime] = []
    @State private var query = ""
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        NavigationStack {
            ScrollView {
                if loading { ProgressView().padding() }
                if let error { Text(error).foregroundStyle(.red).padding() }
                if titles.isEmpty && !loading && error == nil { Text("Ничего не найдено").padding() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 20) {
                    ForEach(titles) { anime in
                        NavigationLink(value: anime) {
                            VStack(alignment: .leading) {
                                AsyncImage(url: URL(string: anime.poster)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: { Rectangle().fill(.gray.opacity(0.2)) }
                                .frame(height: 210).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(anime.title).font(.subheadline.bold()).lineLimit(2)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding()
            }
            .navigationTitle("AniCrN")
            .toolbar { NavigationLink { WebSourceView() } label: { Label("Веб-источник", systemImage: "network") } }
            .searchable(text: $query, prompt: "Поиск AniLiberty")
            .navigationDestination(for: Anime.self) { DetailView(anime: $0) }
            .task(id: query) {
                loading = true
                error = nil
                do {
                    try await Task.sleep(nanoseconds: 350_000_000)
                    let results = try await Provider.catalog(query: query)
                    try Task.checkCancellation()
                    titles = results
                    loading = false
                } catch {
                    if !Task.isCancelled { self.error = error.localizedDescription; loading = false }
                }
            }
        }.tint(.orange)
    }
}

struct Episode: Decodable, Identifiable {
    let id: String
    let name: String?
    let ordinal: Double?
    let hls_1080: String?
    let hls_720: String?
    let hls_480: String?
    var stream: URL? {
        guard let raw = hls_1080 ?? hls_720 ?? hls_480, !raw.isEmpty else { return nil }
        if raw.hasPrefix("//") { return URL(string: "https:" + raw) }
        return URL(string: raw, relativeTo: URL(string: "https://cache.libria.fun/"))?.absoluteURL
    }
}

struct Release: Decodable { let episodes: [Episode]? }
struct DetailView: View {
    let anime: Anime
    @State private var episodes: [Episode] = []
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        List {
            Text(anime.description)
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            if !loading && episodes.isEmpty && error == nil { Text("Серии пока отсутствуют") }
            ForEach(episodes) { episode in
                NavigationLink(episode.name ?? "Серия \(episode.ordinal.map { String($0) } ?? "")") {
                    EpisodeSourcesView(episodeID: episode.id)
                }
            }
        }.navigationTitle(anime.title)
        .task {
            do {
                let id = anime.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? anime.id
                let data = try await Provider.request("/anime/releases/" + id)
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let unwrapped = try JSONSerialization.data(withJSONObject: object?["data"] ?? object ?? [:])
                episodes = (try JSONDecoder().decode(Release.self, from: unwrapped).episodes ?? [])
                    .sorted { ($0.ordinal ?? .greatestFiniteMagnitude) < ($1.ordinal ?? .greatestFiniteMagnitude) }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

struct EpisodeSourcesView: View {
    let episodeID: String
    @State private var episode: Episode?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        List {
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            if let episode {
                ForEach(sources(episode), id: \.0) { quality, url in
                    NavigationLink(quality) { PlaybackView(url: url) }
                }
                if sources(episode).isEmpty { Text("Источник не вернул доступных потоков") }
            }
            Button("Обновить потоки") { Task { await load() } }.disabled(loading)
        }.navigationTitle("Качество AniLiberty").task { await load() }
    }
    private func sources(_ episode: Episode) -> [(String, URL)] {
        [("1080p", episode.hls_1080), ("720p", episode.hls_720), ("480p", episode.hls_480)].compactMap { quality, raw in
            guard let raw, !raw.isEmpty else { return nil }
            let normalized = raw.hasPrefix("//") ? "https:" + raw : raw.replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: normalized, relativeTo: URL(string: "https://cache.libria.fun/"))?.absoluteURL,
                  ["https", "http"].contains(url.scheme ?? "") else { return nil }
            return (quality, url)
        }
    }
    private func load() async {
        loading = true; error = nil
        do {
            let id = episodeID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? episodeID
            let data = try await Provider.request("/anime/releases/episodes/" + id)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let unwrapped = try JSONSerialization.data(withJSONObject: object?["data"] ?? object?["response"] ?? object ?? [:])
            episode = try JSONDecoder().decode(Episode.self, from: unwrapped)
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct PlaybackView: View {
    @State private var player: AVPlayer
    private let loader: MP4ResourceLoader?
    init(url: URL, cookies: [HTTPCookie] = [], headers: [String: String] = [:]) {
        let resourceLoader = url.pathExtension.lowercased() == "mp4" && !headers.isEmpty ? MP4ResourceLoader(url: url, headers: headers, cookies: cookies) : nil
        loader = resourceLoader
        let asset = AVURLAsset(url: resourceLoader?.assetURL ?? url, options: [AVURLAssetHTTPCookiesKey: cookies])
        if let resourceLoader { asset.resourceLoader.setDelegate(resourceLoader, queue: .main) }
        _player = State(initialValue: AVPlayer(playerItem: AVPlayerItem(asset: asset)))
    }
    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player.play() }
            .onDisappear { player.pause() }
    }
}


