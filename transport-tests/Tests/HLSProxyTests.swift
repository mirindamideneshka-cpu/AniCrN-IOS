import XCTest
import Foundation
import Network
#if canImport(TransportChecks)
@testable import TransportChecks
#endif

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
        received.expectedFulfillmentCount = 2
        fixture.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 32768) { data, _, _, _ in
                let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
                XCTAssertTrue(text.lowercased().contains("referer: https://source.test/"))
                XCTAssertTrue(text.lowercased().contains("origin: https://source.test"))
                received.fulfill()
                if text.hasPrefix("GET /segment.ts?sig=abc ") {
                    XCTAssertTrue(text.lowercased().contains("range: bytes=1-3"))
                    let bytes = Data([1, 2, 3])
                    var response = Data("HTTP/1.1 206 Partial Content\r\nContent-Type: video/mp2t\r\nContent-Range: bytes 1-3/5\r\nAccept-Ranges: bytes\r\nContent-Length: 3\r\nConnection: close\r\n\r\n".utf8)
                    response.append(bytes)
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                    return
                }
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
            guard let path = body.components(separatedBy: "\n").first(where: { $0.hasPrefix("http://127.0.0.1:") }), let segment = URL(string: path) else { XCTFail("missing segment route"); response.fulfill(); return }
            var segmentRequest = URLRequest(url: segment)
            segmentRequest.setValue("bytes=1-3", forHTTPHeaderField: "Range")
            URLSession.shared.dataTask(with: segmentRequest) { bytes, result, error in
                XCTAssertNil(error)
                XCTAssertEqual((result as? HTTPURLResponse)?.statusCode, 206)
                XCTAssertEqual((result as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range"), "bytes 1-3/5")
                XCTAssertEqual(bytes, Data([1, 2, 3]))
                response.fulfill()
            }.resume()
        }.resume()
        wait(for: [received, response], timeout: 15)
    }
}
