//
//  FlatProgressBar.swift
//  Melodee
//

import AppKit

/// A flat capsule seek bar, matching the one in the iPhone app's Now Playing screen.
/// The fill brightens and the bar thickens while it's dragged, and it seeks once released.
final class FlatProgressBar: NSView {

    var maxValue: Double = 1 {
        didSet { needsDisplay = true }
    }
    var doubleValue: Double = 0 {
        didSet { needsDisplay = true }
    }
    var isEnabled: Bool = true {
        didSet { needsDisplay = true }
    }
    private(set) var isDragging = false
    /// Called with the time under the pointer while dragging.
    var onScrub: ((Double) -> Void)?
    /// Called with the chosen time when the drag ends.
    var onSeek: ((Double) -> Void)?

    private static let barHeight: CGFloat = 6
    private static let activeBarHeight: CGFloat = 8

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 12)
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let height = isDragging ? Self.activeBarHeight : Self.barHeight
        let track = NSRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        NSColor.secondaryLabelColor.withAlphaComponent(0.3).setFill()
        NSBezierPath(roundedRect: track, xRadius: height / 2, yRadius: height / 2).fill()
        guard isEnabled, maxValue > 0 else { return }
        let progress = min(max(doubleValue / maxValue, 0), 1)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: track, xRadius: height / 2, yRadius: height / 2).addClip()
        NSColor.labelColor.withAlphaComponent(isDragging ? 1.0 : 0.5).setFill()
        NSRect(x: 0, y: track.minY, width: track.width * progress, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, maxValue > 0 else { return }
        isDragging = true
        scrub(to: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        scrub(to: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        scrub(to: event)
        isDragging = false
        needsDisplay = true
        onSeek?(doubleValue)
    }

    private func scrub(to event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        doubleValue = min(max(x / max(bounds.width, 1), 0), 1) * maxValue
        onScrub?(doubleValue)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
