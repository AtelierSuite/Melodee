import SwiftUI

struct ListFileRow: View {

    @Environment(MediaPlayerManager.self) var mediaPlayer
    @Environment(FileDownloadManager.self) var downloadManager

    @Binding var file: FSFile
    var subtitle: String?
    @State var thumbnail: UIImage?
    @State var isThumbnailFetchCompleted: Bool = false
    @State var isEvicted: Bool = false
    @State var fileSizeText: String = ""

    var body: some View {
        HStack(alignment: .center, spacing: 16.0) {
            if file.isTaggableAudio() || file.type == .image,
               let thumbnail = thumbnail {
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
                    .overlay(alignment: .bottomTrailing) {
                        file.type.icon()
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16.0, height: 16.0)
                            .foregroundStyle(file.type.iconColor)
                            .offset(x: 6.0, y: 6.0)
                    }
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
                Text(subtitle ?? fileSizeText)
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
            if file.type == .audio {
                Text(file.extension.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6.0)
                    .padding(.vertical, 3.0)
                    .background(.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 4.0))
            }
        }
        .task(id: file.path) {
            await loadFileMetadata()
        }
        .onChange(of: downloadManager.isDownloading(file)) { wasDownloading, isDownloading in
            // When a download finishes, refresh eviction state, size and thumbnail
            if wasDownloading && !isDownloading {
                isThumbnailFetchCompleted = false
                Task { await loadFileMetadata() }
            }
        }
    }

    /// Reads eviction status and file size off the main thread and caches them in state.
    private func loadFileMetadata() async {
        let path = file.path
        let wantSize = (subtitle == nil)
        let result = await Task.detached(priority: .utility) { () -> (evicted: Bool, sizeText: String) in
            let evicted = FSFile.isEvicted(atPath: path)
            let sizeText = wantSize ? URL(filePath: path).fileSizeString : ""
            return (evicted, sizeText)
        }.value
        isEvicted = result.evicted
        fileSizeText = result.sizeText
        if !result.evicted && !isThumbnailFetchCompleted {
            fetchThumbnail()
        }
    }

    private func fetchThumbnail() {
        isThumbnailFetchCompleted = true
        guard file.isTaggableAudio() || file.type == .image else { return }
        Task {
            if let thumbnail = await FileThumbnailLoader.thumbnail(for: file, size: 100.0, scale: 1.0) {
                withAnimation(.default.speed(2)) {
                    self.thumbnail = thumbnail
                }
            }
        }
    }
}
