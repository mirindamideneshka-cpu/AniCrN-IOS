import SwiftUI
import SwiftSoup

enum DirectStreamResolver {
    static func streams(in text: String, base: URL) throws -> [URL] {
        let rawURLs: [String] = try text.withCString { input in
            guard let output = anicrn_extract_streams(input) else { throw URLError(.cannotParseResponse) }
            defer { anicrn_free(output) }
            return try JSONDecoder().decode([String].self, from: Data(String(cString: output).utf8))
        }
        return rawURLs.compactMap { HTMLProviders.absolute($0, base: base) }
    }
    static func vostPlayers(in html: String, page: URL) throws -> [ProviderEntry] {
        let block = try NSRegularExpression(pattern: #"var\s+data\s*=\s*\{(.*?)\}\s*;"#, options: .dotMatchesLineSeparators)
        guard let match = block.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let range = Range(match.range(at: 1), in: html) else { return [] }
        let body = String(html[range])
        let entry = try NSRegularExpression(pattern: #""([^"]+)"\s*:\s*"([^"]+)""#)
        var seen = Set<String>()
        return entry.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap { match in
            guard let titleRange = Range(match.range(at: 1), in: body), let idRange = Range(match.range(at: 2), in: body) else { return nil }
            let id = String(body[idRange])
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            var c = URLComponents(url: page, resolvingAgainstBaseURL: true)!
            c.path = "/mplay/index.php"; c.queryItems = [URLQueryItem(name: "id", value: id)]
            return ProviderEntry(id: id, title: String(body[titleRange]), url: c.url)
        }
    }
}

struct ResolvedPlayerView: View {
    let player: URL
    let referer: URL
    let isVost: Bool
    @State private var streams: [URL] = []
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        List {
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(streams, id: \.absoluteString) { url in
                NavigationLink("Прямой поток · " + url.pathExtension.uppercased()) {
                    let mediaReferer = isVost ? referer : player
                    PlaybackView(url: url, headers: ["Referer": mediaReferer.absoluteString, "Origin": (mediaReferer.scheme ?? "https") + "://" + (mediaReferer.host ?? "")])
                }
            }
            NavigationLink("Открыть веб-плеер и перехватить поток") { WebSourceView(initialURL: player, referer: referer) }
        }.navigationTitle("Источники видео").task {
            do {
                var endpoint = player
                if isVost {
                    var c = URLComponents(url: player, resolvingAgainstBaseURL: true)!
                    c.path = "/getlink.php"; endpoint = c.url!
                }
                let text = try await HTMLProviders.get(endpoint, referer: referer)
                streams = try DirectStreamResolver.streams(in: text, base: endpoint)
                if endpoint.host == "aniboom.one" || endpoint.host?.hasSuffix(".aniboom.one") == true {
                    let doc = try SwiftSoup.parse(text)
                    if let raw = try doc.select("video[data-parameters]").first()?.attr("data-parameters"),
                       let data = raw.data(using: .utf8), let parameters = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        var hls = parameters["hls"] as? [String: Any]
                        if let nested = parameters["hls"] as? String, let nestedData = nested.data(using: .utf8) { hls = try JSONSerialization.jsonObject(with: nestedData) as? [String: Any] }
                        if let raw = hls?["src"] as? String, let url = HTMLProviders.absolute(raw, base: endpoint), !streams.contains(url) { streams.insert(url, at: 0) }
                    }
                }
                if streams.isEmpty && endpoint.host?.contains("sibnet.ru") == true {
                    let regex = try NSRegularExpression(pattern: #"src:\s*["']([^"']+\.mp4[^"']*)["']"#)
                    for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                        guard let range = Range(match.range(at: 1), in: text), let url = HTMLProviders.absolute(String(text[range]), base: endpoint) else { continue }
                        if !streams.contains(url) { streams.append(url) }
                    }
                }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

