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
                if source == .animefox, let iframe = entries.first?.url {
                    let playerHTML = try await HTMLProviders.get(iframe, referer: page)
                    let playerDoc = try SwiftSoup.parse(playerHTML)
                    let season = try playerDoc.select(".serial-seasons-box option[selected]").first()?.attr("value")
                        ?? playerDoc.select(".serial-seasons-box option").first()?.attr("value") ?? "1"
                    for option in try playerDoc.select(".serial-series-box option[data-id][data-hash]").array() {
                        if try option.attr("data-other-translation") == "true" { continue }
                        let episode = try option.attr("value")
                        guard let number = Int(episode), number > 0 else { continue }
                        var c = URLComponents(url: iframe, resolvingAgainstBaseURL: true)!
                        c.queryItems = (c.queryItems ?? []).filter { !["season", "episode"].contains($0.name) }
                            + [URLQueryItem(name: "season", value: season), URLQueryItem(name: "episode", value: episode)]
                        guard let url = c.url, seen.insert(url.absoluteString).inserted else { continue }
                        entries.append(ProviderEntry(id: url.absoluteString, title: "Сезон \(season) · серия \(episode)", url: url))
                    }
                    let seasons = try playerDoc.select(".serial-seasons-box option[value]").array()
                    for seasonOption in seasons {
                        try Task.checkCancellation()
                        let other = try seasonOption.attr("value")
                        guard other != season, let number = Int(other), number > 0 else { continue }
                        var seasonURL = URLComponents(url: iframe, resolvingAgainstBaseURL: true)!
                        seasonURL.queryItems = (seasonURL.queryItems ?? []).filter { !["season", "episode"].contains($0.name) } + [URLQueryItem(name: "season", value: other)]
                        guard let url = seasonURL.url else { continue }
                        // Keep the season available even if its episode HTML cannot be fetched.
                        entries.append(ProviderEntry(id: "season-" + other, title: "Сезон \(other) · веб-плеер", url: url))
                        let otherHTML = try await HTMLProviders.get(url, referer: page)
                        let otherDoc = try SwiftSoup.parse(otherHTML)
                        for option in try otherDoc.select(".serial-series-box option[data-id][data-hash]").array() {
                            if try option.attr("data-other-translation") == "true" { continue }
                            let episode = try option.attr("value")
                            guard let value = Int(episode), value > 0 else { continue }
                            var selected = seasonURL
                            selected.queryItems = (selected.queryItems ?? []) + [URLQueryItem(name: "episode", value: episode)]
                            guard let selectedURL = selected.url, seen.insert(selectedURL.absoluteString).inserted else { continue }
                            entries.append(ProviderEntry(id: selectedURL.absoluteString, title: "Сезон \(other) · серия \(episode)", url: selectedURL))
                        }
                    }
                }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

