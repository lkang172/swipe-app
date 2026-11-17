import AVFoundation
import Photos
import SwiftUI

struct AssetImage: View {
    let asset: PHAsset
    let size: CGSize
    @Environment(Library.self) private var library
    @State private var image: UIImage?
    @State private var request: PHImageRequestID?

    static let options: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        return options
    }()

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            request = library.images.requestImage(for: asset, targetSize: size, contentMode: .aspectFit,
                                                  options: Self.options) { result, _ in
                guard let result else { return }
                DispatchQueue.main.async { image = result }
            }
        }
        .onDisappear {
            if let request { library.images.cancelImageRequest(request) }
        }
    }
}

@Observable
final class VideoLoop {
    var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var request: PHImageRequestID?

    func start(_ asset: PHAsset, muted: Bool) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        request = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
            guard let item else { return }
            DispatchQueue.main.async {
                guard self.request != nil else { return }
                let player = AVQueuePlayer()
                player.isMuted = muted
                self.looper = AVPlayerLooper(player: player, templateItem: item)
                self.player = player
                player.play()
            }
        }
    }

    func stop() {
        if let request { PHImageManager.default().cancelImageRequest(request) }
        request = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
    }
}

struct LoopingVideo: View {
    let asset: PHAsset
    let muted: Bool
    @State private var video = VideoLoop()

    var body: some View {
        ZStack {
            if let player = video.player {
                PlayerLayer(player: player)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { video.start(asset, muted: muted) }
        .onDisappear { video.stop() }
        .onChange(of: muted) { video.player?.isMuted = muted }
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct PlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        view.playerLayer.player = player
    }
}
