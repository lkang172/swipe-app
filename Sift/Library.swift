import Photos
import SwiftUI

struct Source: Identifiable, Hashable {
    static let allID = "all"
    let id: String
    let title: String
    let count: Int
}

struct Decision: Codable {
    let id: String
    let delete: Bool
}

@MainActor
@Observable
final class Library {
    var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var sources: [Source] = []
    var deleteError: String?
    private(set) var stack: [Decision] = []
    private(set) var isDeleting = false

    private(set) var openID: String?
    private var assets: PHFetchResult<PHAsset>?
    private var ids: [String] = []
    private var index: [String: Int] = [:]
    private var decided: Set<String> = []
    private var cursor = 0
    private(set) var remaining = 0

    let images = PHCachingImageManager()

    private static var file: URL {
        URL.applicationSupportDirectory.appending(path: "decisions.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.file),
           let saved = try? JSONDecoder().decode([Decision].self, from: data) {
            stack = saved
            decided = Set(saved.map(\.id))
        }
    }

    var pendingDeletes: Int { stack.filter(\.delete).count }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    static func mediaOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d",
                                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        return options
    }

    func loadSources() {
        var result = [Source(id: Source.allID, title: "All Photos",
                             count: PHAsset.fetchAssets(with: Self.mediaOptions()).count)]
        var collections: [PHAssetCollection] = []
        let smart: [PHAssetCollectionSubtype] = [
            .smartAlbumFavorites, .smartAlbumVideos, .smartAlbumScreenshots, .smartAlbumSelfPortraits,
            .smartAlbumLivePhotos, .smartAlbumPanoramas, .smartAlbumBursts,
        ]
        for subtype in smart {
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
                .enumerateObjects { collection, _, _ in collections.append(collection) }
        }
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            .enumerateObjects { collection, _, _ in collections.append(collection) }
        for collection in collections {
            let count = PHAsset.fetchAssets(in: collection, options: Self.mediaOptions()).count
            if count > 0 {
                result.append(Source(id: collection.localIdentifier,
                                     title: collection.localizedTitle ?? "Album", count: count))
            }
        }
        sources = result
    }

    func open(_ source: Source) {
        images.stopCachingImagesForAllAssets()
        let fetched: PHFetchResult<PHAsset>
        if source.id == Source.allID {
            fetched = PHAsset.fetchAssets(with: Self.mediaOptions())
        } else if let collection = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [source.id], options: nil).firstObject {
            fetched = PHAsset.fetchAssets(in: collection, options: Self.mediaOptions())
        } else {
            fetched = PHAsset.fetchAssets(withLocalIdentifiers: [], options: nil)
        }
        var newIDs: [String] = []
        newIDs.reserveCapacity(fetched.count)
        fetched.enumerateObjects { asset, _, _ in newIDs.append(asset.localIdentifier) }
        assets = fetched
        ids = newIDs
        index = Dictionary(newIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        remaining = newIDs.filter { !decided.contains($0) }.count
        cursor = 0
        openID = source.id
        advance()
    }

    func upcoming(_ n: Int) -> [PHAsset] {
        guard let assets else { return [] }
        var result: [PHAsset] = []
        var i = cursor
        while i < ids.count && result.count < n {
            if !decided.contains(ids[i]) { result.append(assets.object(at: i)) }
            i += 1
        }
        return result
    }

    func decide(_ asset: PHAsset, delete: Bool) {
        guard !decided.contains(asset.localIdentifier) else { return }
        stack.append(Decision(id: asset.localIdentifier, delete: delete))
        decided.insert(asset.localIdentifier)
        remaining -= 1
        advance()
    }

    func undo() {
        guard let last = stack.lastIndex(where: { index[$0.id] != nil }),
              let position = index[stack[last].id] else { return }
        decided.remove(stack[last].id)
        stack.remove(at: last)
        remaining += 1
        cursor = min(cursor, position)
    }

    func startOver() {
        let cleared = Set(stack.filter { !$0.delete && index[$0.id] != nil }.map(\.id))
        stack.removeAll { cleared.contains($0.id) }
        decided.subtract(cleared)
        remaining += cleared.count
        cursor = 0
        advance()
        save()
    }

    func commitDeletes(then reopen: Source?) async {
        guard !isDeleting else { return }
        let ids = stack.filter(\.delete).map(\.id)
        guard !ids.isEmpty else { return }
        isDeleting = true
        defer { isDeleting = false }
        var deletable: [PHAsset] = []
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            if asset.canPerform(.delete) { deletable.append(asset) }
        }
        if !deletable.isEmpty {
            let request = deletable as NSArray
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(request)
                }
            } catch {
                let failure = error as NSError
                if !(failure.domain == PHPhotosErrorDomain && failure.code == PHPhotosError.Code.userCancelled.rawValue) {
                    deleteError = failure.localizedDescription
                }
                return
            }
        }
        let gone = Set(ids)
        stack.removeAll { gone.contains($0.id) }
        decided.subtract(gone)
        save()
        loadSources()
        if let reopen { open(reopen) }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(stack) else { return }
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory,
                                                 withIntermediateDirectories: true)
        try? data.write(to: Self.file, options: .atomic)
    }

    private func advance() {
        while cursor < ids.count && decided.contains(ids[cursor]) { cursor += 1 }
    }
}
