import XCTest
import Foundation
import Network
@testable import TransportChecks

final class HLSProxyTests: XCTestCase {
    func testLoopbackFetchesAndRewritesPlaylist() throws {
        let queue = DispatchQueue(label: "fixture.http")
        let fixture = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "fixture listening")
        var port: UInt16 = 0
        fixture.stateUpdateHandler = { state in
            if case .ready = state { port = fixture.port!.rawValue; ready.fulfill() }
        }
        let received = expectation(description: "upstream headers")
        fixture.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 32768) { data, _, _, _ in
                let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
                XCTAssertTrue(text.lowercased().contains("referer: https://source.test/"))
                XCTAssertTrue(text.lowercased().contains("origin: https://source.test"))
                received.fulfill()
                let body = "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nsegment.ts?sig=abc\n#EXT-X-ENDLIST\n"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: application/vnd.apple.mpegurl\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        fixture.start(queue: queue)
        wait(for: [ready], timeout: 10)
        defer { fixture.cancel() }
        let proxy = HLSProxy(headers: ["Referer": "https://source.test/", "Origin": "https://source.test"], cookies: [])
        defer { proxy.stop() }
        let started = expectation(description: "proxy ready")
        var local: URL?
        proxy.start(url: URL(string: "http://127.0.0.1:\(port)/master.m3u8")!) { result in
            local = try? result.get(); started.fulfill()
        }
        wait(for: [started], timeout: 10)
        let response = expectation(description: "playlist response")
        guard let local else { XCTFail("proxy failed to start"); return }
        URLSession.shared.dataTask(with: local) { data, result, error in
            XCTAssertNil(error)
            XCTAssertEqual((result as? HTTPURLResponse)?.statusCode, 200)
            let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("#EXTM3U"))
            XCTAssertFalse(body.contains("segment.ts?sig=abc"))
            XCTAssertTrue(body.contains("http://127.0.0.1:"))
            response.fulfill()
        }.resume()
        wait(for: [received, response], timeout: 15)
    }
}
