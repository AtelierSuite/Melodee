//
//  QueueCellView.swift
//  Melodee
//

import AppKit

/// A queue row showing the track's album art or thumbnail, its name, and a speaker when it is playing.
final class QueueCellView: NSTableCellView {

    static let artworkSize: CGFloat = 28
    static let rowHeight: CGFloat = 36

    private let artworkView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let playingIndicator = NSImageView()
    private var thumbnailTask: Task<Void, Never>?
    private var representedPath: String?

    init() {
        super.init(frame: .zero)
        artworkView.imageScaling = .scaleProportionallyUpOrDown
        artworkView.wantsLayer = true
        artworkView.layer?.cornerRadius = 4
        artworkView.layer?.masksToBounds = true
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        playingIndicator.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)
        playingIndicator.contentTintColor = .controlAccentColor
        playingIndicator.setContentHuggingPriority(.required, for: .horizontal)
        playingIndicator.setContentCompressionResistancePriority(.required, for: .horizontal)
        for subview in [artworkView, nameLabel, playingIndicator] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        imageView = artworkView
        textField = nameLabel
        NSLayoutConstraint.activate([
            artworkView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            artworkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            artworkView.widthAnchor.constraint(equalToConstant: Self.artworkSize),
            artworkView.heightAnchor.constraint(equalToConstant: Self.artworkSize),
            nameLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            playingIndicator.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            playingIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            playingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the file's icon straight away, then its album art or thumbnail once it has loaded.
    func configure(with file: FSFile, isCurrent: Bool) {
        thumbnailTask?.cancel()
        representedPath = file.path
        nameLabel.stringValue = file.name
        nameLabel.toolTip = file.name
        nameLabel.font = isCurrent
            ? .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            : .systemFont(ofSize: NSFont.systemFontSize)
        playingIndicator.isHidden = !isCurrent

        let cache = ThumbnailCache.shared
        if let cached = cache.cachedThumbnail(for: file) {
            artworkView.image = cached
            return
        }
        artworkView.image = NSWorkspace.shared.icon(forFile: file.path)
        let scale = window?.backingScaleFactor ?? 2.0
        // The cache is shared with the grid, so load at the grid's size to keep its thumbnails sharp
        let size = BrowserGridItem.iconSizeRange.upperBound
        thumbnailTask = Task { [weak self] in
            guard let image = await cache.thumbnail(for: file, size: size, scale: scale),
                  !Task.isCancelled, let self, representedPath == file.path else { return }
            artworkView.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        representedPath = nil
    }
}
