import XCTest
import AVFoundation
import CoreVideo
import Network
#if canImport(TransportChecks)
@testable import TransportChecks
#endif

final class NativePlaybackTests: XCTestCase {
    func testGeneratedVideoBecomesPlayable() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<10 {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error ?? URLError(.cannotCreateFile) }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer), kCVReturnSuccess)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), 0, CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(index), timescale: 10)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
        let bytes = try Data(contentsOf: url)
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "MP4 fixture ready")
        listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        let queue = DispatchQueue(label: "native.mp4.fixture")
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 32768) { data, _, _, _ in
                let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
                XCTAssertTrue(request.lowercased().contains("referer: https://source.test/"))
                let line = request.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("range:") }
                let range = line?.components(separatedBy: "=").last?.split(separator: "-", omittingEmptySubsequences: false)
                let start = range.flatMap { Int($0[0]) } ?? 0
                let end = min(bytes.count - 1, range.flatMap { $0.count > 1 ? Int($0[1]) : nil } ?? bytes.count - 1)
                guard start <= end, start >= 0 else { connection.cancel(); return }
                let body = bytes.subdata(in: start..<(end + 1))
                var response = Data("HTTP/1.1 206 Partial Content\r\nContent-Type: video/mp4\r\nAccept-Ranges: bytes\r\nContent-Range: bytes \(start)-\(end)/\(bytes.count)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
                response.append(body)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
        await fulfillment(of: [ready], timeout: 10)
        defer { listener.cancel() }
        let remote = URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/fixture.mp4")!
        let loader = MP4ResourceLoader(url: remote, headers: ["Referer": "https://source.test/"], cookies: [])
        let asset = AVURLAsset(url: loader.assetURL)
        asset.resourceLoader.setDelegate(loader, queue: .main)
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.play()
        defer { player.pause() }
        defer { withExtendedLifetime(loader) {} }
        for _ in 0..<100 {
            if item.status == .failed { throw item.error ?? URLError(.cannotDecodeContentData) }
            if player.currentTime().seconds > 0.1 { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("AVPlayer did not advance generated video")
    }
}
