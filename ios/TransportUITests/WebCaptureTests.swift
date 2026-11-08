import XCTest
import WebKit

@MainActor
final class WebCaptureTests: XCTestCase, WKScriptMessageHandler {
    private var received: XCTestExpectation?
    private var urls: [String] = []
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: String], let url = body["url"] else { return }
        urls.append(url)
        XCTAssertEqual(body["type"], "hls")
        received?.fulfill()
    }
    func testActualWebKitScriptBridge() async throws {
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        controller.add(self, name: "anicrnStream")
        defer { controller.removeScriptMessageHandler(forName: "anicrnStream") }
        controller.addUserScript(WKUserScript(source: StreamCaptureBrowser.script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: configuration)
        received = expectation(description: "WebKit captured media")
        view.loadHTMLString("<html><body><video src='https://fixture.invalid/stream.m3u8?sig=abc'></video></body></html>", baseURL: URL(string: "https://source.invalid/"))
        await fulfillment(of: [try XCTUnwrap(received)], timeout: 15)
        XCTAssertEqual(urls, ["https://fixture.invalid/stream.m3u8?sig=abc"])
        view.stopLoading()
    }
}
