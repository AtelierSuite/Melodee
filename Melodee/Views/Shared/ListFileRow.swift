import SwiftUI

struct ListFileRow: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer
    @Environment(FileDownloadManager.self) var downloadManager

    @Binding var file: FSFile
    @State var thumbnail: UIImage?
    @State var isThumbnailFetchCompleted: Bool = false
    @State var isEvicted: Bool = false
    @State var subtitle: String?

    private var hasThumbnail: Bool {
        file.isTaggableAudio() || file.type == .image || file.type == .video
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16.0) {
            if hasThumbnail, let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28.0, height: 28.0)
                    .clipShape(RoundedRectangle(cornerRadius: 6.0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6.0)
                            .stroke(.primary, lineWidth: 1/3)
                            .opacity(0.3)
                    )
            } else {
                file.type.icon()
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28.0, height: 28.0)
                    .foregroundStyle(file.type.iconColor)
            }
            VStack(alignment: .leading, spacing: 2.0) {
                Text(file.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle ?? " ")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if downloadManager.isDownloading(file) {
                if let progress = downloadManager.progress(for: file), progress > 0.0 {
                    CircularProgressView(progress: progress)
                        .frame(width: 16.0, height: 16.0)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            } else if isEvicted {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: file.path) {
            await loadFileMetadata()
        }
        .onChange(of: downloadManager.isDownloading(file)) { wasDownloading, isDownloading in
            // When a download finishes, refresh eviction state, subtitle and thumbnail
            if wasDownloading && !isDownloading {
                isThumbnailFetchCompleted = false
                Task { await loadFileMetadata() }
            }
        }
    }

    /// Reads eviction status and the metadata subtitle off the main thread and caches them in state.
    private func loadFileMetadata() async {
        let result = await FileSubtitleLoader.load(for: file)
        isEvicted = result.isEvicted
        subtitle = result.subtitle
        if !result.isEvicted && !isThumbnailFetchCompleted {
            fetchThumbnail()
        }
    }

    private func fetchThumbnail() {
        isThumbnailFetchCompleted = true
        guard hasThumbnail else { return }
        Task {
            if let thumbnail = await FileThumbnailLoader.thumbnail(for: file, size: 100.0, scale: 1.0) {
                withAnimation(.default.speed(2)) {
                    self.thumbnail = thumbnail
                }
            }
        }
    }
}
