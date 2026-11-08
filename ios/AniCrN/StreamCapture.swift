import SwiftUI
import WebKit
import AVKit

struct CapturedStream: Identifiable {
    var id: String { url.absoluteString }
    let url: URL
    let page: URL?
    let cookies: [HTTPCookie]
}

// Observation of page-level fetch/XHR, resource timing and HTML media in all frames.
// WKWebView does not expose Android's shouldInterceptRequest for HTTPS.
struct StreamCaptureBrowser: UIViewRepresentable {
    let url: URL
    let onStream: (CapturedStream) -> Void
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onStream: onStream, onError: onError) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.add(context.coordinator, name: "anicrnStream")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "anicrnStream")
        view.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onStream: (CapturedStream) -> Void
        let onError: (String) -> Void
        var seen = Set<String>()
        init(onStream: @escaping (CapturedStream) -> Void, onError: @escaping (String) -> Void) {
            self.onStream = onStream; self.onError = onError
        }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: String], let raw = body["url"],
                  let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  ["m3u8", "mp4"].contains(url.pathExtension.lowercased()), seen.insert(raw).inserted else { return }
            let page = message.frameInfo.request.url
            // Preserve domain/path/secure attributes; AVFoundation selects matching cookies.
            message.webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                self?.onStream(CapturedStream(url: url, page: page, cookies: cookies))
            }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onError(error.localizedDescription) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onError(error.localizedDescription) }
    }
    static let script = #"""
    (() => {
      const seen = new Set();
      const report = raw => {
        try {
          const u = new URL(raw, location.href);
          if (!/^https?:$/.test(u.protocol) || !/\.(m3u8|mp4)$/i.test(u.pathname) || seen.has(u.href)) return;
          seen.add(u.href);
          window.webkit.messageHandlers.anicrnStream.postMessage({url: u.href});
        } catch (_) {}
      };
      const fetch = window.fetch;
      window.fetch = function(input, init) {
        report(typeof input === 'string' ? input : input.url);
        return fetch.apply(this, arguments).then(response => { report(response.url); return response; });
      };
      const open = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        report(url);
        this.addEventListener('load', () => report(this.responseURL), {once:true});
        return open.apply(this, arguments);
      };
      try { new PerformanceObserver(list => list.getEntries().forEach(e => report(e.name))).observe({entryTypes:['resource']}); } catch (_) {}
      const scan = () => document.querySelectorAll('video,audio,source').forEach(v => { report(v.currentSrc || v.src); });
      document.addEventListener('loadedmetadata', scan, true);
      document.addEventListener('DOMContentLoaded', () => {
        scan(); new MutationObserver(scan).observe(document.documentElement, {subtree:true, childList:true, attributes:true, attributeFilter:['src']});
      });
    })();
    """#
}

struct WebSourceView: View {
    init(initialURL: URL = URL(string: "https://animego.me")!) {
        _address = State(initialValue: initialURL.absoluteString)
        _page = State(initialValue: initialURL)
    }
    @State private var address = "https://animego.me"
    @State private var page: URL?
    @State private var streams: [CapturedStream] = []
    @State private var error: String?
    var body: some View {
        VStack {
            HStack {
                TextField("HTTPS-страница источника", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Открыть") {
                    guard let url = URL(string: address), url.scheme == "https", url.host != nil else { error = "Введите HTTPS-адрес"; return }
                    streams = []; error = nil; page = url
                }
            }.padding()
            if let error { Text(error).foregroundStyle(.red) }
            if let page {
                StreamCaptureBrowser(url: page, onStream: { stream in
                    if !streams.contains(where: { $0.id == stream.id }) { streams.append(stream) }
                }, onError: { error = $0 }).id(page)
            } else { Text("Откройте источник, выберите серию и запустите видео на странице.").padding(); Spacer() }
            if !streams.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(streams.enumerated()), id: \.element.id) { index, stream in
                            NavigationLink("Поток \(index + 1) · \(stream.url.pathExtension.uppercased())") {
                                PlaybackView(url: stream.url, cookies: stream.cookies, headers: stream.page.map { ["Referer": $0.absoluteString, "Origin": ($0.scheme ?? "https") + "://" + ($0.host ?? "")] } ?? [:])
                            }
                        }
                    }.padding()
                }
                Text("Защищённый заголовками поток может работать только внутри страницы.").font(.caption).padding(.horizontal)
            }
        }.navigationTitle("Веб-источник")
    }
}
