import Vision
import Photos
import UIKit

actor FeaturePrintStore {
    static let shared = FeaturePrintStore()

    private var entries: [String: Data]
    private var storedRevision: Int
    private let storeURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("feature_print_index.plist")
        storeURL = url

        if let fileData = try? Data(contentsOf: url),
           let dict = try? PropertyListSerialization.propertyList(from: fileData, format: nil) as? [String: Any],
           let loadedEntries = dict["entries"] as? [String: Data],
           let loadedRevision = dict["revision"] as? Int {
            entries = loadedEntries
            storedRevision = loadedRevision
        } else {
            entries = [:]
            storedRevision = 0
        }
    }

    var indexedCount: Int { entries.count }

    // MARK: - Incremental indexing

    func buildIndex(onProgress: @escaping @Sendable (Int, Int) -> Void) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return }

        let currentRevision = currentFeaturePrintRevision()

        if currentRevision != storedRevision {
            entries.removeAll()
            storedRevision = currentRevision
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        let total = allPhotos.count

        let currentIds = Set((0..<total).map { allPhotos.object(at: $0).localIdentifier })
        for id in Set(entries.keys).subtracting(currentIds) {
            entries.removeValue(forKey: id)
        }

        let existingIds = Set(entries.keys)
        var newAssets: [PHAsset] = []
        for i in 0..<total {
            let asset = allPhotos.object(at: i)
            if !existingIds.contains(asset.localIdentifier) {
                newAssets.append(asset)
            }
        }

        guard !newAssets.isEmpty else {
            onProgress(1, 1)
            return
        }

        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        let size = CGSize(width: 300, height: 300)

        for (idx, asset) in newAssets.enumerated() {
            var thumbnail: UIImage?
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
                thumbnail = image
            }

            if let photo = thumbnail,
               let observation = computeFeaturePrint(for: photo),
               let archived = try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true) {
                entries[asset.localIdentifier] = archived
            }

            if (idx + 1) % 20 == 0 || idx == newAssets.count - 1 {
                onProgress(idx + 1, newAssets.count)
                await Task.yield()
            }

            if (idx + 1) % 500 == 0 {
                saveToDisk()
            }
        }

        saveToDisk()
    }

    // MARK: - Search (memory-bounded, top-N only)

    struct SearchResult: Sendable {
        let identifier: String
        let distance: Float
    }

    func search(queryImage: UIImage, limit: Int) -> [SearchResult] {
        guard let queryPrint = computeFeaturePrint(for: queryImage) else { return [] }

        var topN: [(id: String, distance: Float)] = []
        var worstInTopN: Float = .infinity

        for (id, data) in entries {
            guard let cached = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: VNFeaturePrintObservation.self, from: data
            ) else { continue }

            var distance: Float = .infinity
            try? queryPrint.computeDistance(&distance, to: cached)

            if topN.count < limit {
                topN.append((id, distance))
                if topN.count == limit {
                    topN.sort { $0.distance < $1.distance }
                    worstInTopN = topN.last!.distance
                }
            } else if distance < worstInTopN {
                topN[limit - 1] = (id, distance)
                topN.sort { $0.distance < $1.distance }
                worstInTopN = topN.last!.distance
            }
        }

        topN.sort { $0.distance < $1.distance }
        return topN.map { SearchResult(identifier: $0.id, distance: $0.distance) }
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let dict: [String: Any] = ["entries": entries, "revision": storedRevision]
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: dict, format: .binary, options: 0
        ) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: - Vision

    private func computeFeaturePrint(for image: UIImage) -> VNFeaturePrintObservation? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try? handler.perform([request])
        return request.results?.first as? VNFeaturePrintObservation
    }

    private func currentFeaturePrintRevision() -> Int {
        VNGenerateImageFeaturePrintRequest().revision
    }
}

extension FeaturePrintStore {
    nonisolated static func loadThumbnails(for identifiers: [String], size: CGSize = CGSize(width: 300, height: 300)) -> [UIImage] {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat

        var images: [UIImage] = []
        for id in identifiers {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
            guard let asset = result.firstObject else { continue }
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                if let image { images.append(image) }
            }
        }
        return images
    }
}
