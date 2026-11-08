import SwiftUI
import AVKit

final class PlaybackSession: ObservableObject {
    let player: AVPlayer
    private let loader: MP4ResourceLoader?
    private var proxy: HLSProxy?
    private var observation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    @Published var error: String?
    init(url: URL, cookies: [HTTPCookie], headers: [String: String]) {
        let loader = url.pathExtension.lowercased() == "mp4" && !headers.isEmpty ? MP4ResourceLoader(url: url, headers: headers, cookies: cookies) : nil
        self.loader = loader
        player = AVPlayer()
        if url.pathExtension.lowercased() == "m3u8" && !headers.isEmpty {
            let proxy = HLSProxy(headers: headers, cookies: cookies)
            self.proxy = proxy
            proxy.start(url: url) { [weak self] result in
                switch result {
                case .success(let local): self?.attach(AVPlayerItem(url: local)); self?.player.play()
                case .failure(let error): self?.error = error.localizedDescription
                }
            }
            return
        }
        let asset = AVURLAsset(url: loader?.assetURL ?? url, options: [AVURLAssetHTTPCookiesKey: cookies])
        if let loader { asset.resourceLoader.setDelegate(loader, queue: .main) }
        attach(AVPlayerItem(asset: asset))
    }
    private func attach(_ item: AVPlayerItem) {
        player.replaceCurrentItem(with: item)
        observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Не удалось открыть поток"
            DispatchQueue.main.async { self?.error = message }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] notification in
            self?.error = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "Воспроизведение прервано"
        }
    }
    deinit {
        player.pause()
        proxy?.stop()
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    }
}

struct PlaybackView: View {
    @StateObject private var session: PlaybackSession
    init(url: URL, cookies: [HTTPCookie] = [], headers: [String: String] = [:]) {
        _session = StateObject(wrappedValue: PlaybackSession(url: url, cookies: cookies, headers: headers))
    }
    var body: some View {
        VStack {
            VideoPlayer(player: session.player)
            if let error = session.error {
                Text(error).foregroundStyle(.red).padding()
                Text("Вернитесь к источнику и получите свежую ссылку либо откройте веб-плеер.").font(.caption).padding()
            }
        }.onAppear { session.player.play() }.onDisappear { session.player.pause() }
    }
}
