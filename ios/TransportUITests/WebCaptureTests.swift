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
        let window = try XCTUnwrap(UIApplication.shared.windows.first(where: { $0.isKeyWindow }))
        window.rootViewController?.view.addSubview(view)
        defer { view.removeFromSuperview() }
        received = expectation(description: "WebKit captured media")
        received?.expectedFulfillmentCount = 2
        view.loadHTMLString("<html><body><video src='https://fixture.invalid/stream.m3u8?sig=abc'></video><iframe srcdoc=\"&lt;video src='https://fixture.invalid/frame.m3u8'&gt;&lt;/video&gt;\"></iframe></body></html>", baseURL: URL(string: "https://source.invalid/"))
        await fulfillment(of: [try XCTUnwrap(received)], timeout: 15)
        XCTAssertEqual(urls.sorted(), ["https://fixture.invalid/frame.m3u8", "https://fixture.invalid/stream.m3u8?sig=abc"])
        view.stopLoading()
    }
}
