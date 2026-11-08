import Foundation

enum HLSPlaylist {
    static func rewrite(_ playlist: String, base: URL, route: (URL) -> URL) -> String {
        let uri = try! NSRegularExpression(pattern: #"URI="([^"]+)""#)
        func resolve(_ value: String) -> URL? {
            guard let url = URL(string: value, relativeTo: base)?.absoluteURL,
                  ["http", "https"].contains(url.scheme ?? "") else { return nil }
            return url
        }
        return playlist.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.hasPrefix("#"), !trimmed.isEmpty, let url = resolve(trimmed) { return route(url).absoluteString }
            var result = line
            for match in uri.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
                guard let range = Range(match.range(at: 1), in: line), let url = resolve(String(line[range])), let replace = Range(match.range(at: 1), in: result) else { continue }
                result.replaceSubrange(replace, with: route(url).absoluteString)
            }
            return result
        }.joined(separator: "\n")
    }
}
