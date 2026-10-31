//
//  BrowserGridItem.swift
//  Melodee
//

import AppKit

/// A file's album art or thumbnail with its name beneath, highlighted the way Finder's icon view does.
final class BrowserGridItem: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("BrowserGridItem")
    static let iconSize: CGFloat = 96

    private let iconBackground = NSView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(wrappingLabelWithString: "")
    private var representedURL: URL?
    private var thumbnailTask: Task<Void, Never>?

    override var isSelected: Bool {
        didSet { updateHighlight() }
    }

    override func loadView() {
        let container = NSView()
        iconBackground.wantsLayer = true
        iconBackground.layer?.cornerRadius = 8
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 6
        iconView.layer?.masksToBounds = true
        nameLabel.alignment = .center
        nameLabel.maximumNumberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        nameLabel.wantsLayer = true
        nameLabel.layer?.cornerRadius = 4
        for subview in [iconBackground, iconView, nameLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            iconBackground.topAnchor.constraint(equalTo: container.topAnchor),
            iconBackground.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconBackground.widthAnchor.constraint(equalToConstant: Self.iconSize + 8),
            iconBackground.heightAnchor.constraint(equalToConstant: Self.iconSize + 8),
            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),
            nameLabel.topAnchor.constraint(equalTo: iconBackground.bottomAnchor, constant: 4),
            nameLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            nameLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
        ])
        view = container
        imageView = iconView
        textField = nameLabel
    }

    /// Shows the file's icon straight away, then its album art or thumbnail once it has loaded.
    func configure(with item: BrowserItem) {
        thumbnailTask?.cancel()
        representedURL = item.url
        nameLabel.stringValue = item.name
        nameLabel.toolTip = item.name
        let cache = ThumbnailCache.shared
        iconView.image = cache.cachedThumbnail(for: item) ?? NSWorkspace.shared.icon(forFile: item.url.path)
        updateHighlight()
        guard !item.isFolder, cache.cachedThumbnail(for: item) == nil else { return }
        let scale = view.window?.backingScaleFactor ?? 2.0
        thumbnailTask = Task { [weak self] in
            guard let image = await cache.thumbnail(for: item, size: Self.iconSize, scale: scale),
                  !Task.isCancelled, let self, representedURL == item.url else { return }
            iconView.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        representedURL = nil
    }

    private func updateHighlight() {
        iconBackground.layer?.backgroundColor = isSelected
            ? NSColor.quaternaryLabelColor.cgColor
            : NSColor.clear.cgColor
        nameLabel.layer?.backgroundColor = isSelected
            ? NSColor.selectedContentBackgroundColor.cgColor
            : NSColor.clear.cgColor
        nameLabel.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
    }
}
