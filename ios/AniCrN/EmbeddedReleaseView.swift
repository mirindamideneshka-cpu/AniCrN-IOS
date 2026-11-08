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
                if let url = entry.url { NavigationLink(entry.title) { ResolvedPlayerView(player: url, referer: page, isVost: source == .animevost) } }
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
                    entries += try DirectStreamResolver.vostPlayers(in: html, page: page)
                }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

