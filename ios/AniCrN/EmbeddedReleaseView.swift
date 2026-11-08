import SwiftUI
import SwiftSoup

struct EmbeddedReleaseView: View {
    let source: AnimeSource
    let page: URL
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
            NavigationLink("Открыть плеер на странице") { WebSourceView(initialURL: page) }
        }.navigationTitle(source.title).task {
            do {
                let html = try await HTMLProviders.get(page, referer: source.site)
                let doc = try SwiftSoup.parse(html)
                var seen = Set<String>()
                entries = try doc.select(source == .animefox ? "iframe.iframePlayer[src]" : "iframe[src]").array().compactMap { iframe in
                    guard let url = try HTMLProviders.absolute(iframe.attr("src"), base: page), seen.insert(url.absoluteString).inserted else { return nil }
                    return ProviderEntry(id: url.absoluteString, title: "Плеер · " + (url.host ?? source.title), url: url)
                }
                if source == .animevost {
                    let normalized = html.replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "&amp;", with: "&")
                    let pattern = #"["']([^"']*(?:серия|Серия)[^"']*)["']\s*:\s*["']?(\d+)"#
                    let regex = try NSRegularExpression(pattern: pattern)
                    for match in regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
                        guard let nameRange = Range(match.range(at: 1), in: normalized), let idRange = Range(match.range(at: 2), in: normalized) else { continue }
                        var c = URLComponents(url: page, resolvingAgainstBaseURL: true)!
                        c.path = "/mplay/index.php"; c.queryItems = [URLQueryItem(name: "id", value: String(normalized[idRange]))]
                        guard let url = c.url, seen.insert(url.absoluteString).inserted else { continue }
                        entries.append(ProviderEntry(id: url.absoluteString, title: String(normalized[nameRange]), url: url))
                    }
                }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}
