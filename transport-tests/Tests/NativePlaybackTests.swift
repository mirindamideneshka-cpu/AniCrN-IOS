import XCTest
import AVFoundation
import CoreVideo

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
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.play()
        defer { player.pause() }
        for _ in 0..<100 {
            if item.status == .failed { throw item.error ?? URLError(.cannotDecodeContentData) }
            if player.currentTime().seconds > 0.1 { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("AVPlayer did not advance generated video")
    }
}
