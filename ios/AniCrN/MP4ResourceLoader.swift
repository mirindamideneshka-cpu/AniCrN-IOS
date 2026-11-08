import AVFoundation
import UniformTypeIdentifiers

// Public AVAssetResourceLoader path for progressive MP4 byte ranges.
// HLS is intentionally kept on AVFoundation's HTTP stack until a playlist proxy exists.
final class MP4ResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    let original: URL
    let headers: [String: String]
    let cookies: [HTTPCookie]
    private var transfers: [ObjectIdentifier: Transfer] = [:]
    init(url: URL, headers: [String: String], cookies: [HTTPCookie]) {
        original = url; self.headers = headers; self.cookies = cookies
    }
    var assetURL: URL {
        var c = URLComponents(url: original, resolvingAgainstBaseURL: true)!
        c.scheme = "anicrn-mp4"
        return c.url!
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        let key = ObjectIdentifier(request)
        let transfer = Transfer(request: request, url: original, headers: headers, cookies: cookies) { [weak self] in self?.transfers.removeValue(forKey: key) }
        transfers[key] = transfer
        transfer.start()
        return true
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        transfers.removeValue(forKey: ObjectIdentifier(request))?.cancel()
    }
    deinit { transfers.values.forEach { $0.cancel() } }

    private final class Transfer: NSObject, URLSessionDataDelegate {
        let request: AVAssetResourceLoadingRequest
        let url: URL
        let headers: [String: String]
        let cookies: [HTTPCookie]
        let done: () -> Void
        var session: URLSession?
        var task: URLSessionDataTask?
        var position: Int64 = 0
        var finished = false
        var startOffset: Int64 { request.dataRequest.map { max($0.requestedOffset, $0.currentOffset) } ?? 0 }
        init(request: AVAssetResourceLoadingRequest, url: URL, headers: [String: String], cookies: [HTTPCookie], done: @escaping () -> Void) {
            self.request = request; self.url = url; self.headers = headers; self.cookies = cookies; self.done = done
        }
        func start() {
            let config = URLSessionConfiguration.ephemeral
            cookies.forEach { config.httpCookieStorage?.setCookie($0) }
            session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
            var upstream = URLRequest(url: url)
            upstream.timeoutInterval = 30
            headers.forEach { upstream.setValue($1, forHTTPHeaderField: $0) }
            if let data = request.dataRequest {
                let end = data.requestsAllDataToEndOfResource ? "" : String(data.requestedOffset + Int64(data.requestedLength) - 1)
                upstream.setValue("bytes=\(startOffset)-\(end)", forHTTPHeaderField: "Range")
            } else { upstream.httpMethod = "HEAD" }
            task = session?.dataTask(with: upstream); task?.resume()
        }
        func cancel() { finished = true; task?.cancel(); session?.invalidateAndCancel() }
        func finish(_ error: Error? = nil) {
            guard !finished else { return }; finished = true
            if let error { request.finishLoading(with: error) } else { request.finishLoading() }
            task?.cancel(); session?.invalidateAndCancel(); done()
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let http = response as? HTTPURLResponse, [200,206].contains(http.statusCode) else {
                completionHandler(.cancel); finish(URLError(.badServerResponse)); return
            }
            let range = http.value(forHTTPHeaderField: "Content-Range") ?? ""
            let total = range.split(separator: "/").last.flatMap { Int64($0) }
            position = http.statusCode == 206 ? startOffset : 0
            if let info = request.contentInformationRequest {
                info.contentType = UTType(mimeType: http.mimeType ?? "video/mp4")?.identifier ?? UTType.mpeg4Movie.identifier
                info.contentLength = total ?? response.expectedContentLength
                info.isByteRangeAccessSupported = http.statusCode == 206 || http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes"
            }
            completionHandler(.allow)
            if request.dataRequest == nil { finish() }
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard !finished, let target = request.dataRequest else { return }
            let next = position + Int64(data.count)
            let wanted = max(target.requestedOffset, target.currentOffset)
            let end = target.requestsAllDataToEndOfResource ? next : min(next, target.requestedOffset + Int64(target.requestedLength))
            if end > max(position, wanted) {
                let offset = Int(max(position, wanted) - position)
                target.respond(with: data.subdata(in: offset..<Int(end - position)))
            }
            position = next
            if !target.requestsAllDataToEndOfResource && target.currentOffset >= target.requestedOffset + Int64(target.requestedLength) { finish() }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { finish(error) }
    }
}
