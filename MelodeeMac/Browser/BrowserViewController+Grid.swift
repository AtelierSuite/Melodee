//
//  BrowserViewController+Grid.swift
//  Melodee
//

import AppKit

extension BrowserViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {

    func configureGrid() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = BrowserGridItem.itemSize(forIconSize: gridIconSize)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(BrowserGridItem.self, forItemWithIdentifier: BrowserGridItem.identifier)
        collectionView.menu = makeContextMenu()
        collectionView.onOpen = { [weak self] indexes in
            self?.openItems(at: indexes)
        }
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: BrowserGridItem.identifier, for: indexPath)
        if let gridItem = item as? BrowserGridItem {
            gridItem.iconSize = gridIconSize
            gridItem.configure(with: items[indexPath.item])
        }
        return item
    }

    /// Pinching scales the icons, as in Finder's icon view.
    @objc func handlePinch(_ recognizer: NSMagnificationGestureRecognizer) {
        switch recognizer.state {
        case .began:
            pinchStartIconSize = gridIconSize
        case .changed, .ended:
            setGridIconSize(pinchStartIconSize * (1 + recognizer.magnification))
        default:
            break
        }
    }

    func setGridIconSize(_ size: CGFloat) {
        let range = BrowserGridItem.iconSizeRange
        let newSize = min(max(size, range.lowerBound), range.upperBound).rounded()
        guard newSize != gridIconSize else { return }
        gridIconSize = newSize
        (collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize =
            BrowserGridItem.itemSize(forIconSize: newSize)
        for case let item as BrowserGridItem in collectionView.visibleItems() {
            item.iconSize = newSize
        }
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        selectionDidChange(to: IndexSet(collectionView.selectionIndexPaths.map(\.item)))
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        selectionDidChange(to: IndexSet(collectionView.selectionIndexPaths.map(\.item)))
    }

    // MARK: - Drag and drop

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> (any NSPasteboardWriting)? {
        items[indexPath.item].url as NSURL
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: any NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        proposedDropOperation.pointee = .before
        return validateFileDrop(draggingInfo)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: any NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        acceptFileDrop(draggingInfo)
    }
}
