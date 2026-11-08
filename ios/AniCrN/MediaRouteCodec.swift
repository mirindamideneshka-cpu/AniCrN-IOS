import Foundation
import CryptoKit

// Authenticated, encrypted loopback routes avoid retaining every segment URL in memory.
final class MediaRouteCodec {
    private let key = SymmetricKey(size: .bits256)
    func encode(_ url: URL) throws -> String {
        let sealed = try AES.GCM.seal(Data(url.absoluteString.utf8), using: key)
        guard let data = sealed.combined else { throw URLError(.badURL) }
        let token = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "/" + token + "." + (url.pathExtension.isEmpty ? "bin" : url.pathExtension)
    }
    func decode(_ path: String) -> URL? {
        guard path.hasPrefix("/"), path.utf8.count < 32768 else { return nil }
        let raw = String(path.dropFirst()).components(separatedBy: ".").first ?? ""
        var base64 = raw.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), let box = try? AES.GCM.SealedBox(combined: data),
              let decoded = try? AES.GCM.open(box, using: key), let value = String(data: decoded, encoding: .utf8),
              let url = URL(string: value), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { return nil }
        return url
    }
}
