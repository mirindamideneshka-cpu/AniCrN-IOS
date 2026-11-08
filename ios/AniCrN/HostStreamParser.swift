import Foundation
import SwiftSoup

enum HostStreamParser {
    static func parse(_ html: String, page: URL) throws -> [URL] {
        var sources: [URL] = []
        func add(_ raw: String) {
            guard let url = URL(string: raw.replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "&amp;", with: "&"), relativeTo: page)?.absoluteURL,
                  ["https", "http"].contains(url.scheme ?? ""), !sources.contains(url) else { return }
            sources.append(url)
        }
        let host = page.host?.lowercased() ?? ""
        if host == "aniboom.one" || host.hasSuffix(".aniboom.one") {
            let doc = try SwiftSoup.parse(html)
            if let raw = try doc.select("video[data-parameters]").first()?.attr("data-parameters"), let data = raw.data(using: .utf8) {
                let parameters = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                var hls = parameters?["hls"] as? [String: Any]
                if let nested = parameters?["hls"] as? String, let data = nested.data(using: .utf8) { hls = try JSONSerialization.jsonObject(with: data) as? [String: Any] }
                if let raw = hls?["src"] as? String { add(raw) }
            }
        }
        if host == "video.sibnet.ru" || host.hasSuffix(".sibnet.ru") {
            let regex = try NSRegularExpression(pattern: #"src:\s*["']([^"']+\.mp4[^"']*)["']"#)
            for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                if let range = Range(match.range(at: 1), in: html) { add(String(html[range])) }
            }
        }
        return sources
    }
}
