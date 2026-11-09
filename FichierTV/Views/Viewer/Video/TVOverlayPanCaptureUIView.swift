//
//  TVOverlayPanCaptureUIView.swift
//  FichierTV
//
//

import UIKit

/// Attaches a horizontal Siri Remote touchpad `UIPanGestureRecognizer` onto the overlay's host view container
/// so indirect finger swipes scrub smoothly only while the HUD progress row holds Focus Engine focus.
///
/// NOTE: UIKit is utilized here because SwiftUI on tvOS does not expose Siri Remote indirect touch-surface
/// translation and velocity for continuous scrubbing gestures.
@MainActor
public final class TVOverlayPanCaptureUIView: UIView, UIGestureRecognizerDelegate {
    public var isScrubberSwipeEnabled: Bool = false

    public var onPanChanged: (@MainActor (_ incrementalDeltaX: CGFloat, _ velocityX: CGFloat, _ hostWidth: CGFloat) -> Void)?
    public var onPanEnded: (@MainActor () -> Void)?
    public var onPanCancelled: (@MainActor () -> Void)?

    private lazy var panGestureRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = self
        return recognizer
    }()

    private weak var attachedHostView: UIView?
    private var lastTranslationX: CGFloat = 0

    public override var canBecomeFocused: Bool {
        false
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil {
            detachGestureRecognizer()
        }
        super.willMove(toWindow: newWindow)
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        attachGestureRecognizerIfNeeded()
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard window != nil else { return }
        attachGestureRecognizerIfNeeded()
    }

    /// Evaluates whether a swipe should enter scrub tracking vs allow normal vertical Focus Engine navigation.
    public func shouldBeginSwipe(translation: CGPoint, velocity: CGPoint) -> Bool {
        guard isScrubberSwipeEnabled else { return false }
        let horizontalScore = max(abs(translation.x), abs(velocity.x) * 0.05)
        let verticalScore = max(abs(translation.y), abs(velocity.y) * 0.05)
        return horizontalScore > verticalScore * 1.25
    }

    /// Processes synthetic or real pan deltas cleanly across gesture lifecycle phases.
    public func processPanEvent(
        incrementalDeltaX: CGFloat,
        velocityX: CGFloat,
        trackWidth: CGFloat,
        state: UIGestureRecognizer.State
    ) {
        switch state {
        case .began:
            lastTranslationX = 0
            if incrementalDeltaX != 0 {
                onPanChanged?(incrementalDeltaX, velocityX, trackWidth)
            }
        case .changed:
            onPanChanged?(incrementalDeltaX, velocityX, trackWidth)
        case .ended:
            lastTranslationX = 0
            onPanEnded?()
        case .cancelled, .failed:
            lastTranslationX = 0
            onPanCancelled?()
        default:
            break
        }
    }

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        guard let hostView = attachedHostView else {
            return false
        }
        let translation = panGestureRecognizer.translation(in: hostView)
        let velocity = panGestureRecognizer.velocity(in: hostView)
        return shouldBeginSwipe(translation: translation, velocity: velocity)
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let hostView = attachedHostView else { return }

        switch recognizer.state {
        case .began:
            lastTranslationX = 0
            let currentX = recognizer.translation(in: hostView).x
            let velocityX = recognizer.velocity(in: hostView).x
            lastTranslationX = currentX
            processPanEvent(
                incrementalDeltaX: currentX,
                velocityX: velocityX,
                trackWidth: hostView.bounds.width,
                state: .began
            )

        case .changed:
            let currentX = recognizer.translation(in: hostView).x
            let delta = currentX - lastTranslationX
            lastTranslationX = currentX
            let velocityX = recognizer.velocity(in: hostView).x
            processPanEvent(
                incrementalDeltaX: delta,
                velocityX: velocityX,
                trackWidth: hostView.bounds.width,
                state: .changed
            )

        case .ended:
            processPanEvent(
                incrementalDeltaX: 0,
                velocityX: 0,
                trackWidth: hostView.bounds.width,
                state: .ended
            )

        case .cancelled, .failed:
            processPanEvent(
                incrementalDeltaX: 0,
                velocityX: 0,
                trackWidth: hostView.bounds.width,
                state: .cancelled
            )

        default:
            break
        }
    }

    private func attachGestureRecognizerIfNeeded() {
        let targetHost = resolveOverlayHostView() ?? superview
        guard attachedHostView !== targetHost else { return }
        detachGestureRecognizer()
        guard let targetHost else { return }
        targetHost.addGestureRecognizer(panGestureRecognizer)
        attachedHostView = targetHost
    }

    private func detachGestureRecognizer() {
        if let attachedHostView {
            attachedHostView.removeGestureRecognizer(panGestureRecognizer)
            self.attachedHostView = nil
        }
        lastTranslationX = 0
    }

    private func resolveOverlayHostView() -> UIView? {
        var responder: UIResponder? = next
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController.view
            }
            responder = current.next
        }
        var ancestor = superview
        while let parent = ancestor?.superview, !(parent is UIWindow) {
            ancestor = parent
        }
        return ancestor
    }
}
