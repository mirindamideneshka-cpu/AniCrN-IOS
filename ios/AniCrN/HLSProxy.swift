import Foundation
import Network

// One loopback-only listener per playback session. Opaque routes never expose upstream tokens.
final class HLSProxy {
    private let queue = DispatchQueue(label: "anicrn.hls.proxy")
    private let headers: [String: String]
    private let session: URLSession
    private var listener: NWListener?
    private var routes: [String: URL] = [:]
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]
    private var port: UInt16 = 0
    init(headers: [String: String], cookies: [HTTPCookie]) {
        self.headers = headers
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        cookies.forEach { config.httpCookieStorage?.setCookie($0) }
        session = URLSession(configuration: config)
    }
    func start(url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                var reported = false
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self, !reported else { return }
                    switch state {
                    case .ready:
                        reported = true
                        self.port = listener.port!.rawValue
                        let local = self.route(url)
                        DispatchQueue.main.async { completion(.success(local)) }
                    case .failed(let error):
                        reported = true
                        DispatchQueue.main.async { completion(.failure(error)) }
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.start(queue: self.queue)
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
    private func route(_ url: URL) -> URL {
        let key = UUID().uuidString + "." + (url.pathExtension.isEmpty ? "bin" : url.pathExtension)
        routes["/" + key] = url
        return URL(string: "http://127.0.0.1:\(port)/\(key)")!
    }
    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.start(queue: queue)
        read(connection, accumulated: Data())
        queue.asyncAfter(deadline: .now() + 60) { [weak self, weak connection] in
            guard let self, let connection, self.connections[id] != nil else { return }
            self.close(connection)
        }
    }
    private func close(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        tasks.removeValue(forKey: id)?.cancel()
        connections.removeValue(forKey: id)
        connection.cancel()
    }
    private func read(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, ended, error in
            guard let self else { return }
            var buffer = accumulated; if let data { buffer.append(data) }
            guard buffer.count <= 32768, error == nil else { self.close(connection); return }
            if let text = String(data: buffer, encoding: .utf8), text.contains("\r\n\r\n") { self.handle(connection, text: text) }
            else if ended { self.close(connection) }
            else { self.read(connection, accumulated: buffer) }
        }
    }
    private func handle(_ connection: NWConnection, text: String) {
        let lines = text.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2, ["GET", "HEAD"].contains(String(parts[0])), let url = routes[String(parts[1])] else {
            reply(connection, status: 404, data: Data(), headers: [:]); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = String(parts[0])
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        for line in lines.dropFirst() where line.lowercased().hasPrefix("range:") {
            request.setValue(String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces), forHTTPHeaderField: "Range")
        }
        let task = session.dataTask(with: request) { [weak self, weak connection] data, response, error in
            guard let self, let connection else { return }
            self.queue.async {
                guard error == nil, let http = response as? HTTPURLResponse else { self.reply(connection, status: 502, data: Data(), headers: [:]); return }
                var body = data ?? Data()
                var forwarded: [String: String] = [:]
                for key in ["Content-Type", "Content-Range", "Accept-Ranges"] { forwarded[key] = http.value(forHTTPHeaderField: key) }
                if body.starts(with: Data("#EXTM3U".utf8)), let playlist = String(data: body, encoding: .utf8) {
                    body = Data(self.rewrite(playlist, base: http.url ?? url).utf8)
                    forwarded["Content-Type"] = "application/vnd.apple.mpegurl"
                }
                self.reply(connection, status: http.statusCode, data: body, headers: forwarded)
            }
        }
        tasks[ObjectIdentifier(connection)] = task; task.resume()
    }
    private func rewrite(_ playlist: String, base: URL) -> String {
        HLSPlaylist.rewrite(playlist, base: base, route: route)
    }
    private func reply(_ connection: NWConnection, status: Int, data: Data, headers: [String: String]) {
        var head = "HTTP/1.1 \(status) Response\r\nConnection: close\r\nContent-Length: \(data.count)\r\n"
        for (key, value) in headers { head += "\(key): \(value.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: ""))\r\n" }
        var response = Data((head + "\r\n").utf8); response.append(data)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in self?.close(connection) })
    }
    func stop() {
        queue.async { self.listener?.cancel(); self.listener = nil; Array(self.connections.values).forEach { self.close($0) }; self.routes.removeAll(); self.session.invalidateAndCancel() }
    }
}
