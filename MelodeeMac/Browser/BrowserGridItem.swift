//
//  BrowserGridItem.swift
//  Melodee
//

import AppKit

/// A file's album art or thumbnail with its name beneath, highlighted the way Finder's icon view does.
final class BrowserGridItem: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("BrowserGridItem")
    static let defaultIconSize: CGFloat = 96
    static let iconSizeRange: ClosedRange<CGFloat> = 48...256

    private let iconBackground = NSView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(wrappingLabelWithString: "")
    private var representedURL: URL?
    private var sizeConstraints: [NSLayoutConstraint] = []
    /// Changed by pinching the grid.
    var iconSize: CGFloat = BrowserGridItem.defaultIconSize {
        didSet { updateSizeConstraints() }
    }
    private var thumbnailTask: Task<Void, Never>?

    override var isSelected: Bool {
        didSet { updateHighlight() }
    }

    /// Set while dragging a selection rectangle, before the selection itself changes.
    override var highlightState: NSCollectionViewItem.HighlightState {
        didSet { updateHighlight() }
    }

    private var isHighlighted: Bool {
        switch highlightState {
        case .forSelection, .asDropTarget: true
        case .forDeselection: false
        default: isSelected
        }
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
            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            nameLabel.topAnchor.constraint(equalTo: iconBackground.bottomAnchor, constant: 4),
            nameLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            nameLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
        ])
        sizeConstraints = [
            iconBackground.widthAnchor.constraint(equalToConstant: iconSize + 8),
            iconBackground.heightAnchor.constraint(equalToConstant: iconSize + 8),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize)
        ]
        NSLayoutConstraint.activate(sizeConstraints)
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
            guard let image = await cache.thumbnail(for: item, size: Self.iconSizeRange.upperBound, scale: scale),
                  !Task.isCancelled, let self, representedURL == item.url else { return }
            iconView.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        representedURL = nil
    }

    private func updateSizeConstraints() {
        guard sizeConstraints.count == 4 else { return }
        sizeConstraints[0].constant = iconSize + 8
        sizeConstraints[1].constant = iconSize + 8
        sizeConstraints[2].constant = iconSize
        sizeConstraints[3].constant = iconSize
    }

    /// The cell size that fits an icon of the given size with two lines of name beneath it.
    static func itemSize(forIconSize iconSize: CGFloat) -> NSSize {
        NSSize(width: max(iconSize + 32, 112), height: iconSize + 48)
    }

    private func updateHighlight() {
        iconBackground.layer?.backgroundColor = isHighlighted
            ? NSColor.quaternaryLabelColor.cgColor
            : NSColor.clear.cgColor
        nameLabel.layer?.backgroundColor = isHighlighted
            ? NSColor.selectedContentBackgroundColor.cgColor
            : NSColor.clear.cgColor
        nameLabel.textColor = isHighlighted ? .alternateSelectedControlTextColor : .labelColor
    }
}
