import Foundation

struct YummyVideo: Identifiable {
    let id: String
    let number: String
    let voice: String
    let url: URL
}
enum YummyVideoParser {
    static func parse(_ rows: [[String: Any]], base: URL) -> [YummyVideo] {
        var seen = Set<String>()
        return rows.compactMap { item in
            let number = (item["number"] as? String) ?? (item["number"] as? NSNumber)?.stringValue ?? ""
            guard !number.isEmpty, let raw = item["iframe_url"] as? String,
                  let url = URL(string: raw, relativeTo: base)?.absoluteURL,
                  ["http", "https"].contains(url.scheme ?? "") else { return nil }
            let data = item["data"] as? [String: Any]
            let host = (data?["player"] as? String ?? "").lowercased()
            guard !host.contains("alloha"), !raw.lowercased().contains("alloha") else { return nil }
            let key = number + "|" + url.absoluteString
            guard seen.insert(key).inserted else { return nil }
            let voice = [data?["dubbing"] as? String, data?["player"] as? String].compactMap { $0 }.joined(separator: " / ")
            return YummyVideo(id: key, number: number, voice: voice.isEmpty ? "Плеер" : voice, url: url)
        }
    }
}
