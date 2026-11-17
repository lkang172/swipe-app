import Photos
import SwiftUI

struct DeckView: View {
    let source: Source
    @Environment(Library.self) private var library
    @Environment(\.displayScale) private var scale
    @State private var offset: CGSize = .zero
    @State private var flying = false
    @State private var muted = true

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let size = CGSize(width: geo.size.width * scale, height: geo.size.height * scale)
                let ready = library.openID == source.id
                let cards = ready ? library.upcoming(3) : []
                ZStack {
                    Color.clear
                    if !ready {
                        ProgressView()
                    } else if cards.isEmpty {
                        finished
                    } else {
                        ForEach(Array(cards.prefix(2).enumerated().reversed()), id: \.element.localIdentifier) { i, asset in
                            card(asset, top: i == 0, size: size)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if ready && !flying { library.undo() } }
                .onChange(of: cards.map(\.localIdentifier), initial: true) {
                    library.images.stopCachingImagesForAllAssets()
                    library.images.startCachingImages(for: Array(cards.dropFirst()), targetSize: size,
                                                      contentMode: .aspectFit, options: AssetImage.options)
                }
            }
            Text("Swipe left to delete, right to keep. Tap to undo.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("\(library.remaining) left").font(.subheadline.monospacedDigit())
            }
            ToolbarItem(placement: .topBarTrailing) { DeleteButton(reopen: source) }
        }
        .onAppear { library.open(source) }
    }

    private func card(_ asset: PHAsset, top: Bool, size: CGSize) -> some View {
        let progress = max(-1, min(1, offset.width / 120))
        return ZStack {
            AssetImage(asset: asset, size: size)
            if top && asset.mediaType == .video {
                LoopingVideo(asset: asset, muted: muted)
                    .overlay(alignment: .bottomTrailing) {
                        Button { muted.toggle() } label: {
                            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(12)
                    }
            }
            if top && progress != 0 {
                (progress > 0 ? Color.green : Color.red).opacity(abs(progress) * 0.3)
                Text(progress > 0 ? "KEEP" : "DELETE")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(progress > 0 ? Color.green : Color.red, in: Capsule())
                    .opacity(abs(progress))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .scaleEffect(top ? 1 : 0.95)
        .offset(top ? offset : .zero)
        .rotationEffect(.degrees(top ? Double(offset.width) / 20 : 0))
        .allowsHitTesting(top)
        .gesture(drag(asset))
    }

    private func drag(_ asset: PHAsset) -> some Gesture {
        DragGesture()
            .onChanged { if !flying { offset = $0.translation } }
            .onEnded { value in
                guard !flying else { return }
                let moved = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let far = abs(moved) > 120 || abs(predicted) > 150
                guard far && moved != 0 && (moved > 0) == (predicted > 0) else {
                    withAnimation(.spring) { offset = .zero }
                    return
                }
                let keep = moved > 0
                flying = true
                withAnimation(.easeIn(duration: 0.2)) {
                    offset = CGSize(width: keep ? 800 : -800, height: value.translation.height)
                } completion: {
                    library.decide(asset, delete: !keep)
                    offset = .zero
                    flying = false
                }
            }
    }

    private var finished: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle").font(.system(size: 56)).foregroundStyle(.tint)
            Text("All sorted").font(.title2.bold())
            DeleteButton(reopen: source, prominent: true)
            Button("Start Over") { library.startOver() }
        }
    }
}
