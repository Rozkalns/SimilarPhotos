import SwiftUI
import PhotosUI
import Photos

struct PhotoResult: Identifiable {
    let id: String
    let image: UIImage
    let distance: Float

    var similarityPercent: Int {
        max(0, min(100, Int((1 - distance / 40) * 100)))
    }
}

@MainActor
@Observable
class PhotoSearchViewModel {
    var inputImage: UIImage?
    var results: [PhotoResult] = []
    var isIndexing = false
    var isSearching = false
    var progress: Double = 0
    var statusText = ""
    var indexedCount = 0

    private let store = FeaturePrintStore.shared

    func buildIndex() async {
        isIndexing = true
        indexedCount = await store.indexedCount

        let store = self.store
        let stream = AsyncStream<(Int, Int)> { continuation in
            Task {
                await store.buildIndex { current, total in
                    continuation.yield((current, total))
                }
                continuation.finish()
            }
        }

        for await (current, total) in stream {
            progress = Double(current) / Double(max(total, 1))
            statusText = "Indexing \(current) / \(total) new photos..."
        }

        indexedCount = await store.indexedCount
        isIndexing = false
        statusText = ""
    }

    private var currentLimit = 30

    func search(image: UIImage) async {
        currentLimit = 30
        isSearching = true
        results = []
        statusText = "Searching \(indexedCount) photos..."

        let matches = await store.search(queryImage: image, limit: currentLimit)

        statusText = "Loading results..."
        let ids = matches.map(\.identifier)
        let images = await Task.detached { () -> [UIImage] in
            FeaturePrintStore.loadThumbnails(for: ids)
        }.value

        results = zip(matches, images).map { match, img in
            PhotoResult(id: match.identifier, image: img, distance: match.distance)
        }

        isSearching = false
        statusText = ""
    }

    func loadMore() async {
        guard let image = inputImage else { return }
        currentLimit += 30
        isSearching = true
        statusText = "Loading more..."

        let matches = await store.search(queryImage: image, limit: currentLimit)

        let ids = matches.map(\.identifier)
        let images = await Task.detached { () -> [UIImage] in
            FeaturePrintStore.loadThumbnails(for: ids)
        }.value

        results = zip(matches, images).map { match, img in
            PhotoResult(id: match.identifier, image: img, distance: match.distance)
        }

        isSearching = false
        statusText = ""
    }

    func reject(_ result: PhotoResult) {
        let rejectedPrint = result.distance
        let threshold: Float = 5
        results.removeAll { abs($0.distance - rejectedPrint) < threshold || $0.id == result.id }
    }
}

struct ContentView: View {
    @State private var viewModel = PhotoSearchViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedResult: PhotoResult?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.isIndexing {
                        VStack(spacing: 8) {
                            ProgressView(value: viewModel.progress)
                            Text(viewModel.statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    } else if viewModel.indexedCount > 0 {
                        Text("\(viewModel.indexedCount) photos indexed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    let inputImage = viewModel.inputImage
                    if let image = inputImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    HStack(spacing: 12) {
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Label("Library", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            guard let clipped = UIPasteboard.general.image else { return }
                            viewModel.inputImage = clipped
                            Task {
                                await viewModel.search(image: clipped)
                            }
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.indexedCount == 0)
                    }
                    .disabled(viewModel.indexedCount == 0)

                    if inputImage == nil {
                        ContentUnavailableView(
                            "Select or Paste a Photo",
                            systemImage: "photo.badge.magnifyingglass",
                            description: Text("Pick from library or paste from clipboard")
                        )
                        .frame(minHeight: 150)
                    }

                    if viewModel.isSearching {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text(viewModel.statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    let currentResults = viewModel.results
                    if !currentResults.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(currentResults.count) Similar Photos")
                                .font(.headline)
                            Text("Tap to view · Long press to remove noise")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 4) {
                                ForEach(currentResults) { result in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: result.image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 110, height: 110)
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 6))

                                        Text("\(result.similarityPercent)%")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(similarityColor(result.similarityPercent).opacity(0.85))
                                            .foregroundStyle(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                            .padding(4)
                                    }
                                    .onTapGesture {
                                        selectedResult = result
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            viewModel.reject(result)
                                        } label: {
                                            Label("Not similar — remove noise like this", systemImage: "xmark.circle")
                                        }
                                    }
                                }
                            }

                            Button {
                                Task { await viewModel.loadMore() }
                            } label: {
                                Label("Show More", systemImage: "arrow.down.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 8)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Similar Photos")
            .task {
                await viewModel.buildIndex()
            }
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                selectedItem = nil
                Task { @MainActor in
                    guard let data = try? await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    viewModel.inputImage = image
                    await viewModel.search(image: image)
                }
            }
            .sheet(item: $selectedResult) { result in
                PhotoDetailView(result: result)
            }
        }
    }

    func similarityColor(_ percent: Int) -> Color {
        if percent >= 70 { return .green }
        if percent >= 40 { return .orange }
        return .red
    }
}

struct PhotoDetailView: View {
    let result: PhotoResult
    @Environment(\.dismiss) private var dismiss
    @State private var assetDate: Date?
    @State private var assetLocation: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(uiImage: result.image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if let date = assetDate {
                        VStack(spacing: 4) {
                            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                                .font(.title2.bold())
                            Text(date.formatted(.dateTime.hour().minute()))
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    HStack {
                        Label("\(result.similarityPercent)% match", systemImage: "sparkle.magnifyingglass")
                            .foregroundStyle(result.similarityPercent >= 70 ? .green : result.similarityPercent >= 40 ? .orange : .red)
                        Spacer()
                        if let location = assetLocation {
                            Label(location, systemImage: "location")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Button {
                        if let url = URL(string: "photos-redirect://") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Open Photos App", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Photo Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [result.id], options: nil)
                guard let asset = fetchResult.firstObject else { return }
                assetDate = asset.creationDate
                if let loc = asset.location?.coordinate {
                    assetLocation = String(format: "%.4f, %.4f", loc.latitude, loc.longitude)
                }
            }
        }
    }
}
