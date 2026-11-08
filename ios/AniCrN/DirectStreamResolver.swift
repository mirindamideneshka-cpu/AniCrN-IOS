import SwiftUI

enum DirectStreamResolver {
    static func streams(in text: String, base: URL) throws -> [URL] {
        let decoded = text.replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&").replacingOccurrences(of: "&amp;", with: "&")
        let regex = try NSRegularExpression(pattern: #"(?:https?:)?//[^"'<>\s\\]+\.(?:m3u8|mp4)(?:\?[^"'<>\s\\]*)?"#, options: .caseInsensitive)
        var seen = Set<String>()
        return regex.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)).compactMap { match in
            guard let range = Range(match.range, in: decoded), let url = HTMLProviders.absolute(String(decoded[range]), base: base), seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }
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
                NavigationLink("Прямой поток · " + url.pathExtension.uppercased()) { PlaybackView(url: url) }
            }
            NavigationLink("Открыть веб-плеер и перехватить поток") { WebSourceView(initialURL: player) }
        }.navigationTitle("Источники видео").task {
            do {
                var endpoint = player
                if isVost {
                    var c = URLComponents(url: player, resolvingAgainstBaseURL: true)!
                    c.path = "/getlink.php"; endpoint = c.url!
                }
                let text = try await HTMLProviders.get(endpoint, referer: referer)
                streams = try DirectStreamResolver.streams(in: text, base: endpoint)
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}
