import SwiftUI
import UIKit

/// Lets the Now Playing artwork be swiped left to go to the next track, and right to go back to the previous one.
///
/// The card follows the finger, with a haptic as it crosses the point where letting go changes tracks, and a
/// softer one if it's dragged back under. Without a track to go to, it only gives a little and springs back.
struct NPTrackSwipe: ViewModifier {

    @Environment(MediaPlayerManager.self) var mediaPlayer
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var isEnabled: Bool = true

    @State private var offset: CGFloat = .zero
    @State private var width: CGFloat = .zero
    @State private var isPastThreshold: Bool = false
    @State private var isChangingTrack: Bool = false
    /// Counted rather than toggled, so resetting after a swipe doesn't play a haptic.
    @State private var thresholdCrossings: Int = 0
    @State private var thresholdReturns: Int = 0
    @State private var flickCommits: Int = 0

    /// How far across the card the drag must go for letting go to change tracks.
    static let thresholdFraction: CGFloat = 0.3
    /// How fast a flick must be, in points per second, to change tracks before reaching the threshold.
    static let flickVelocity: CGFloat = 800.0
    /// How far the card can be pulled when there's no track to go to.
    static let rubberBandLimit: CGFloat = 40.0

    private var threshold: CGFloat {
        max(width, 1.0) * Self.thresholdFraction
    }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(1.0 - 0.3 * min(abs(offset) / max(width, 1.0), 1.0))
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
            .gesture(HorizontalPanGesture(isEnabled: isEnabled && mediaPlayer.isPlaybackActive,
                                          onChanged: dragChanged,
                                          onEnded: dragEnded))
            .sensoryFeedback(.impact(weight: .light), trigger: thresholdCrossings)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: thresholdReturns)
            .sensoryFeedback(.impact(weight: .light), trigger: flickCommits)
    }

    private func canChangeTrack(towardsNext: Bool) -> Bool {
        towardsNext ? mediaPlayer.canGoToNextTrack() : mediaPlayer.canGoToPreviousTrack()
    }

    private func dragChanged(_ translation: CGFloat) {
        guard !isChangingTrack else { return }
        if canChangeTrack(towardsNext: translation < 0) {
            offset = translation
            setPastThreshold(abs(translation) >= threshold)
        } else {
            // Give a little, never reaching the threshold, so it's clear there's nowhere to go
            offset = translation * Self.rubberBandLimit / (abs(translation) + Self.rubberBandLimit)
            setPastThreshold(false)
        }
    }

    private func setPastThreshold(_ newValue: Bool) {
        guard newValue != isPastThreshold else { return }
        isPastThreshold = newValue
        if newValue {
            thresholdCrossings += 1
        } else {
            thresholdReturns += 1
        }
    }

    private func dragEnded(_ translation: CGFloat, _ velocity: CGFloat) {
        guard !isChangingTrack else { return }
        let towardsNext = translation < 0
        let isFlick = abs(velocity) >= Self.flickVelocity && (velocity < 0) == towardsNext && translation != 0
        let wasPastThreshold = isPastThreshold
        isPastThreshold = false
        guard canChangeTrack(towardsNext: towardsNext), wasPastThreshold || isFlick else {
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                offset = .zero
            }
            return
        }
        // A flick that never reached the threshold hasn't had its haptic yet
        if !wasPastThreshold {
            flickCommits += 1
        }
        changeTrack(towardsNext: towardsNext)
    }

    private func changeTrack(towardsNext: Bool) {
        isChangingTrack = true
        if reduceMotion {
            // Settle back in place and let the artwork crossfade
            withAnimation(.easeOut(duration: 0.2)) {
                offset = .zero
            }
            performTrackChange(towardsNext: towardsNext)
            isChangingTrack = false
            return
        }
        let exitOffset = (towardsNext ? -1.0 : 1.0) * (width + 48.0)
        withAnimation(.easeIn(duration: 0.18)) {
            offset = exitOffset
        } completion: {
            performTrackChange(towardsNext: towardsNext)
            Task { @MainActor in
                // Give Now Playing a moment to load the new artwork before it slides in
                try? await Task.sleep(for: .milliseconds(60))
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    offset = -exitOffset
                }
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                    offset = .zero
                } completion: {
                    isChangingTrack = false
                }
            }
        }
    }

    private func performTrackChange(towardsNext: Bool) {
        // Always goes to the neighbouring track, even when the buttons skip within the file
        if towardsNext {
            mediaPlayer.skipToNextTrack()
        } else {
            mediaPlayer.backToPreviousTrack()
        }
    }
}

/// A pan that only begins when the finger moves mostly sideways, leaving vertical drags to the
/// list and the sheet around it.
private struct HorizontalPanGesture: UIGestureRecognizerRepresentable {

    var isEnabled: Bool
    let onChanged: (CGFloat) -> Void
    /// Called with the final horizontal translation and velocity. Both are zero if the pan was cancelled.
    let onEnded: (CGFloat, CGFloat) -> Void

    /// How much more sideways than vertical the movement must be for the pan to begin.
    static let horizontalBias: CGFloat = 1.5

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(recognizer.translation(in: recognizer.view).x)
        case .ended:
            onEnded(recognizer.translation(in: recognizer.view).x, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            onEnded(.zero, .zero)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * HorizontalPanGesture.horizontalBias
        }
    }
}
