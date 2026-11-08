import Foundation
import Network

// Streams segment bodies with send completion backpressure; only playlists are buffered.
final class HLSHTTPTransfer: NSObject, URLSessionDataDelegate {
    private let connection: NWConnection
    private let rewrite: (String, URL) -> String
    private let done: () -> Void
    private let queue: DispatchQueue
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var buffer = Data()
    private var playlist = false
    private var decided = false
    private var ended = false
    private var headersSent = false
    private var sendingFailure = false
    private let headOnly: Bool
    init(connection: NWConnection, queue: DispatchQueue, headOnly: Bool, rewrite: @escaping (String, URL) -> String, done: @escaping () -> Void) {
        self.connection = connection; self.queue = queue; self.headOnly = headOnly; self.rewrite = rewrite; self.done = done
    }
    func start(_ request: URLRequest, configuration: URLSessionConfiguration) {
        let operations = OperationQueue(); operations.maxConcurrentOperationCount = 1; operations.underlyingQueue = queue
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: operations)
        task = session?.dataTask(with: request); task?.resume()
    }
    func cancel() { ended = true; task?.cancel(); session?.invalidateAndCancel() }
    private func finish() { guard !ended else { return }; cancel(); done() }
    private func headers(_ http: HTTPURLResponse, length: Int? = nil, chunked: Bool = false) -> Data {
        var text = "HTTP/1.1 \(http.statusCode) Response\r\nConnection: close\r\n"
        for name in ["Content-Type", "Content-Range", "Accept-Ranges"] {
            if name == "Content-Type" && playlist && !headOnly { continue }
            if let value = http.value(forHTTPHeaderField: name) { text += name + ": " + value.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "") + "\r\n" }
        }
        if playlist && !headOnly { text += "Content-Type: application/vnd.apple.mpegurl\r\n" }
        if chunked { text += "Transfer-Encoding: chunked\r\n" }
        else if let length { text += "Content-Length: \(length)\r\n" }
        else if let value = http.value(forHTTPHeaderField: "Content-Length"), let size = Int64(value) { text += "Content-Length: \(size)\r\n" }
        return Data((text + "\r\n").utf8)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard !ended, let http = response as? HTTPURLResponse else { completionHandler(.cancel); finish(); return }
        self.response = http
        playlist = (http.mimeType ?? "").lowercased().contains("mpegurl") || http.url?.pathExtension.lowercased() == "m3u8"
        if headOnly {
            completionHandler(.cancel)
            connection.send(content: headers(http), completion: .contentProcessed { [weak self] _ in self?.finish() })
            return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !ended, let http = response else { return }
        if !decided {
            buffer.append(data)
            guard buffer.count >= 7 else { return }
            playlist = playlist || buffer.starts(with: Data("#EXTM3U".utf8))
            decided = true
            if !playlist {
                connection.send(content: headers(http, chunked: true), completion: .contentProcessed { [weak self] error in if error != nil { self?.finish() } })
                headersSent = true
                let first = buffer; buffer.removeAll(); sendChunk(first)
            }
        } else if playlist { buffer.append(data) }
        else { sendChunk(data) }
        if playlist && buffer.count > 2 * 1024 * 1024 { failHTTP() }
    }
    private func sendChunk(_ data: Data) {
        guard !ended else { return }
        task?.suspend()
        var chunk = Data((String(data.count, radix: 16) + "\r\n").utf8); chunk.append(data); chunk.append(Data("\r\n".utf8))
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self, !self.ended else { return }
            if error != nil { self.finish() } else { self.task?.resume() }
        })
    }
    private func failHTTP() {
        guard !ended else { return }
        guard !headersSent else { finish(); return }
        headersSent = true
        sendingFailure = true
        task?.cancel()
        connection.send(content: Data("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { [weak self] _ in self?.finish() })
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !ended, !headOnly, !sendingFailure else { return }
        guard error == nil, let http = response else { if !headersSent { failHTTP() } else { finish() }; return }
        if playlist {
            guard let text = String(data: buffer, encoding: .utf8), let url = http.url else { failHTTP(); return }
            let body = Data(rewrite(text, url).utf8)
            var output = headers(http, length: body.count); output.append(body)
            connection.send(content: output, completion: .contentProcessed { [weak self] _ in self?.finish() })
        } else {
            if !decided {
                connection.send(content: headers(http, chunked: true), completion: .contentProcessed { _ in })
                if !buffer.isEmpty {
                    var chunk = Data((String(buffer.count, radix: 16) + "\r\n").utf8); chunk.append(buffer); chunk.append(Data("\r\n".utf8))
                    connection.send(content: chunk, completion: .contentProcessed { _ in })
                }
            }
            connection.send(content: Data("0\r\n\r\n".utf8), completion: .contentProcessed { [weak self] _ in self?.finish() })
        }
    }
}
