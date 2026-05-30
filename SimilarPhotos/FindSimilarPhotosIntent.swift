import AppIntents
import UIKit

struct FindSimilarPhotosIntent: AppIntent {
    static var title: LocalizedStringResource = "Find Similar Photos"
    static var description = IntentDescription("Finds visually similar photos in your library using a pre-built index")

    @Parameter(title: "Image")
    var image: IntentFile

    @Parameter(title: "Number of results", default: 10)
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Find \(\.$limit) photos similar to \(\.$image)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        guard let uiImage = UIImage(data: image.data) else {
            throw FindSimilarError.invalidImage
        }

        let store = FeaturePrintStore.shared
        guard await store.indexedCount > 0 else {
            throw FindSimilarError.notIndexed
        }

        let matches = await store.search(queryImage: uiImage, limit: limit)
        let thumbnails = FeaturePrintStore.loadThumbnails(for: matches.map(\.identifier), size: CGSize(width: 512, height: 512))

        let files = thumbnails.compactMap { img -> IntentFile? in
            guard let data = img.jpegData(compressionQuality: 0.85) else { return nil }
            return IntentFile(data: data, filename: "similar.jpg")
        }

        return .result(value: files)
    }
}

enum FindSimilarError: Error, CustomLocalizedStringResourceConvertible {
    case invalidImage
    case notIndexed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidImage: "Could not read the provided image"
        case .notIndexed: "Open the app first to build the photo index"
        }
    }
}

struct SimilarPhotosShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindSimilarPhotosIntent(),
            phrases: [
                "Find similar photos with \(.applicationName)",
                "Search for matching images in \(.applicationName)"
            ],
            shortTitle: "Find Similar",
            systemImageName: "photo.badge.magnifyingglass"
        )
    }
}
