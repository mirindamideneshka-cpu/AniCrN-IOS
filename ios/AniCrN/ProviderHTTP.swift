import Foundation

struct ProviderHTTPError: LocalizedError {
    let status: Int
    let host: String
    var errorDescription: String? { "Источник \(host) вернул HTTP \(status)" }
}

enum ProviderHTTP {
    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw ProviderHTTPError(status: http.statusCode, host: http.url?.host ?? "") }
    }
    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        for attempt in 0..<2 {
            do {
                let result = try await URLSession.shared.data(for: request)
                let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
                if attempt == 0 && canRetry(method: request.httpMethod, status: status, error: nil) {
                    try await Task.sleep(nanoseconds: 400_000_000); continue
                }
                return result
            } catch {
                guard attempt == 0, !Task.isCancelled, canRetry(method: request.httpMethod, status: nil, error: error) else { throw error }
                try await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        throw URLError(.cannotConnectToHost)
    }
    static func canRetry(method: String?, status: Int?, error: Error?) -> Bool {
        guard (method ?? "GET") == "GET" else { return false }
        if let status { return [500, 502, 503, 504].contains(status) }
        guard let error = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code)
    }
}
