import Foundation

enum HomeCatalog {
    static func load(source: AnimeSource, query: String, page: Int) async throws -> [Anime] {
        switch source {
        case .aniliberty: return try await Provider.catalog(query: query, page: page)
        case .animego, .animefox, .animevost:
            return try await HTMLProviders.catalog(source: source, query: query, page: page).map { Anime(id: $0.id, title: $0.title, description: "", poster: "") }
        case .animelib:
            var params = [URLQueryItem(name: "site_id[]", value: "5"), URLQueryItem(name: "page", value: String(page))]
            if !query.isEmpty { params.append(URLQueryItem(name: "q", value: query)) }
            else { params += [URLQueryItem(name: "sort_by", value: "rating_score"), URLQueryItem(name: "sort_type", value: "desc")] }
            let root = try await AnimeLibAPI.request("/anime", query: params)
            return (root["data"] as? [[String: Any]] ?? []).compactMap { row in
                guard let id = row["slug_url"] as? String else { return nil }
                let cover = row["cover"] as? [String: Any]
                return Anime(id: id, title: row["rus_name"] as? String ?? row["name"] as? String ?? id, description: row["summary"] as? String ?? "", poster: cover?["md"] as? String ?? cover?["default"] as? String ?? "")
            }
        case .yummyanime:
            let rows: [[String: Any]]
            if query.isEmpty {
                let feed = try await YummyAPI.request("/feed") as? [String: Any]
                rows = feed?["new_videos"] as? [[String: Any]] ?? []
            } else {
                rows = try await YummyAPI.request("/search", query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "offset", value: String((page - 1) * 30))]) as? [[String: Any]] ?? []
            }
            var seen = Set<String>()
            return rows.compactMap(YummyAPI.title).filter { seen.insert($0.id).inserted }
        case .shikimori:
            var c = URLComponents(string: "https://shikimori.one/api/animes")!
            c.queryItems = [URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "order", value: "popularity")]
            if !query.isEmpty { c.queryItems?.append(URLQueryItem(name: "search", value: query)) }
            let rows = try await ProviderNetwork.json(c.url!, site: source.site) as? [[String: Any]] ?? []
            return rows.compactMap { row in
                guard let id = row["id"] as? NSNumber else { return nil }
                let russian = row["russian"] as? String ?? ""
                let image = row["image"] as? [String: Any]
                let poster = (image?["original"] as? String).flatMap { URL(string: $0, relativeTo: source.site)?.absoluteURL.absoluteString } ?? ""
                return Anime(id: id.stringValue, title: russian.isEmpty ? row["name"] as? String ?? id.stringValue : russian, description: row["description"] as? String ?? "", poster: poster)
            }
        }
    }
}
