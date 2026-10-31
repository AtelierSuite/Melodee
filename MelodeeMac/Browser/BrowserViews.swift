//
//  BrowserViews.swift
//  Melodee
//

import AppKit

/// A collection view that opens items on double-click or Return, and plays or pauses on Space, like Finder and Music.
final class BrowserCollectionView: NSCollectionView {

    var onOpen: ((IndexSet) -> Void)?
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 2 else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let indexPath = indexPathForItem(at: point) {
            onOpen?(IndexSet(integer: indexPath.item))
        }
    }

    override func keyDown(with event: NSEvent) {
        if BrowserKeys.handle(event, selection: IndexSet(selectionIndexPaths.map(\.item)), onOpen: onOpen) {
            return
        }
        // Arrow keys start from the first item when nothing is selected, as in Finder
        let arrowKeys: [NSEvent.SpecialKey] = [.leftArrow, .rightArrow, .upArrow, .downArrow]
        if selectionIndexPaths.isEmpty, let key = event.specialKey, arrowKeys.contains(key), numberOfItems(inSection: 0) > 0 {
            let indexPaths: Set<IndexPath> = [IndexPath(item: 0, section: 0)]
            selectItems(at: indexPaths, scrollPosition: .nearestHorizontalEdge)
            delegate?.collectionView?(self, didSelectItemsAt: indexPaths)
            return
        }
        super.keyDown(with: event)
    }
}

final class BrowserTableView: NSTableView {

    var onOpen: ((IndexSet) -> Void)?

    override func keyDown(with event: NSEvent) {
        if BrowserKeys.handle(event, selection: selectedRowIndexes, onOpen: onOpen) {
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
private enum BrowserKeys {

    static func handle(_ event: NSEvent, selection: IndexSet, onOpen: ((IndexSet) -> Void)?) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.numericPad).isEmpty else {
            return false
        }
        switch event.charactersIgnoringModifiers {
        case "\r", "\u{3}":
            guard !selection.isEmpty else { return false }
            onOpen?(selection)
            return true
        case " ":
            MacServices.shared.player.togglePlayPause()
            return true
        default:
            return false
        }
    }
}
