import SwiftUI

/// A queue entry showing the file's album art or video thumbnail beside its name.
struct NPQueueRow: View {

    @Environment(\.displayScale) var displayScale

    var file: FSFile
    var isCurrent: Bool

    @State private var thumbnail: UIImage?

    private static let artworkSize: CGFloat = 36.0

    var body: some View {
        HStack(alignment: .center, spacing: 12.0) {
            artwork
                .frame(width: Self.artworkSize, height: Self.artworkSize)
                .overlay {
                    if isCurrent {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6.0)
                                .fill(.black.opacity(0.45))
                            Image("Play")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16.0, height: 16.0)
                                .foregroundStyle(.white)
                        }
                    }
                }
            Text(file.name)
                .font(.body)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isCurrent ? AnyShapeStyle(.accent) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .contentShape(Rectangle())
        .task(id: file.path) {
            thumbnail = nil
            // Reading artwork from a file still in iCloud would download it
            let path = file.path
            let isEvicted = await Task.detached(priority: .utility) {
                FSFile.isEvicted(atPath: path)
            }.value
            guard !isEvicted, !Task.isCancelled else { return }
            let image = await FileThumbnailLoader.thumbnail(
                for: file,
                size: Self.artworkSize,
                scale: displayScale,
                includesDocuments: true
            )
            guard !Task.isCancelled else { return }
            withAnimation(.default.speed(2)) {
                thumbnail = image
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: Self.artworkSize, height: Self.artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 6.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 6.0)
                        .stroke(.primary, lineWidth: 1/3)
                        .opacity(0.3)
                )
        } else {
            RoundedRectangle(cornerRadius: 6.0)
                .fill(.quaternary)
                .overlay {
                    file.type.icon()
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20.0, height: 20.0)
                        .foregroundStyle(file.type.iconColor)
                }
        }
    }
}
