import SwiftUI

struct GridFileCell: View {

    @Environment(FileDownloadManager.self) var downloadManager
    @Environment(\.displayScale) var displayScale

    var file: FSFile
    @State var thumbnail: UIImage?
    @State var isThumbnailFetchCompleted: Bool = false
    @State var isEvicted: Bool = false
    @State var subtitle: String?

    var body: some View {
        GridCellLayout(title: file.name, subtitle: subtitle) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    GridCellIcon(image: file.type.icon(), color: file.type.iconColor)
                }
            }
            .overlay(alignment: .topTrailing) {
                downloadStatus
                    .padding(6.0)
            }
            .overlay(alignment: .bottomTrailing) {
                if file.type == .audio {
                    Text(file.extension.uppercased())
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6.0)
                        .padding(.vertical, 3.0)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4.0))
                        .padding(6.0)
                }
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

    @ViewBuilder
    var downloadStatus: some View {
        if downloadManager.isDownloading(file) {
            Group {
                if let progress = downloadManager.progress(for: file), progress > 0.0 {
                    CircularProgressView(progress: progress)
                        .frame(width: 16.0, height: 16.0)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(4.0)
            .background(.regularMaterial, in: .circle)
        } else if isEvicted {
            Image(systemName: "icloud.and.arrow.down")
                .font(.caption)
                .padding(5.0)
                .background(.regularMaterial, in: .circle)
        }
    }

    /// Reads eviction status and the metadata subtitle off the main thread and caches them in state.
    private func loadFileMetadata() async {
        let result = await FileSubtitleLoader.load(for: file)
        isEvicted = result.isEvicted
        subtitle = result.subtitle
        if !result.isEvicted && !isThumbnailFetchCompleted {
            isThumbnailFetchCompleted = true
            if let thumbnail = await FileThumbnailLoader.thumbnail(
                for: file,
                size: GridCell.maximumWidth,
                scale: displayScale,
                includesDocuments: true
            ) {
                withAnimation(.default.speed(2)) {
                    self.thumbnail = thumbnail
                }
            }
        }
    }
}

struct GridFolderCell: View {

    var name: String

    var body: some View {
        GridCellLayout(title: name, subtitle: nil) {
            GridCellIcon(image: Image(systemName: "folder.fill"), color: .accentColor)
        }
    }
}

enum GridCell {
    static let minimumWidth: CGFloat = 96.0
    static let maximumWidth: CGFloat = 160.0
}

/// A square artwork tile with the title and an optional subtitle centered below it, like the icon view in Files.
struct GridCellLayout<Artwork: View>: View {

    var title: String
    var subtitle: String?
    @ViewBuilder var artwork: Artwork

    var body: some View {
        VStack(alignment: .center, spacing: 6.0) {
            Color.clear
                .aspectRatio(1.0, contentMode: .fit)
                .overlay {
                    artwork
                }
                .clipShape(RoundedRectangle(cornerRadius: 10.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 10.0)
                        .stroke(.primary, lineWidth: 1/3)
                        .opacity(0.2)
                )
            VStack(alignment: .center, spacing: 2.0) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                Text(subtitle ?? " ")
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .contentShape(.rect)
    }
}

struct GridCellIcon: View {

    var image: Image
    var color: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(color.opacity(0.12))
            image
                .resizable()
                .scaledToFit()
                .foregroundStyle(color)
                .padding(28.0)
        }
    }
}
