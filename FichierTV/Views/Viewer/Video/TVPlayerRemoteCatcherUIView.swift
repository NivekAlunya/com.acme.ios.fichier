//
//  TVPlayerRemoteCatcherUIView.swift
//  FichierTV
//
//

import UIKit

/// Focusable full-screen `UIView` measuring exact `UIPress` began/ended/cancelled intervals
/// when the HUD overlay is hidden so Siri Remote Left/Right taps and holds drive seeking.
///
/// NOTE: UIKit is utilized here because SwiftUI's `.onMoveCommand` emits discrete directional events
/// without press-to-release duration timing.
@MainActor
public final class TVPlayerRemoteCatcherUIView: UIView {
    public var isFocusCatchingEnabled: Bool = true {
        didSet {
            guard isFocusCatchingEnabled != oldValue else { return }
            setNeedsFocusUpdate()
        }
    }

    public var onSeekPressBegan: (@MainActor (Bool, TimeInterval) -> Void)?
    public var onSeekPressEnded: (@MainActor (Bool, TimeInterval) -> Void)?
    public var onSeekPressCancelled: (@MainActor (Bool) -> Void)?
    public var onRevealOverlay: (@MainActor () -> Void)?

    private var activeSeekPressID: ObjectIdentifier?
    private var activeSeekIsForward: Bool = true
    private var pendingSelectPressID: ObjectIdentifier?
    private var consumedPressIDs: Set<ObjectIdentifier> = []

    public override var canBecomeFocused: Bool {
        isFocusCatchingEnabled
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = "Show video playback controls"
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && isFocusCatchingEnabled {
            setNeedsFocusUpdate()
        }
    }

    public override func accessibilityActivate() -> Bool {
        guard isFocusCatchingEnabled else { return false }
        onRevealOverlay?()
        return true
    }

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isFocusCatchingEnabled else {
            super.pressesBegan(presses, with: event)
            return
        }

        var unhandled: Set<UIPress> = []

        for press in presses {
            let timestamp = resolvedTimestamp(for: press)
            let pressID = ObjectIdentifier(press)

            switch press.type {
            case .leftArrow, .rightArrow:
                let isForward = press.type == .rightArrow
                consumedPressIDs.insert(pressID)

                if activeSeekPressID == nil {
                    activeSeekPressID = pressID
                    activeSeekIsForward = isForward
                    onSeekPressBegan?(isForward, timestamp)
                } else if activeSeekIsForward != isForward {
                    onSeekPressEnded?(activeSeekIsForward, timestamp)
                    activeSeekPressID = pressID
                    activeSeekIsForward = isForward
                    onSeekPressBegan?(isForward, timestamp)
                }

            case .upArrow, .downArrow:
                consumedPressIDs.insert(pressID)
                onRevealOverlay?()

            case .select:
                consumedPressIDs.insert(pressID)
                pendingSelectPressID = pressID

            default:
                unhandled.insert(press)
            }
        }

        if !unhandled.isEmpty {
            super.pressesBegan(unhandled, with: event)
        }
    }

    public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled: Set<UIPress> = []

        for press in presses {
            let pressID = ObjectIdentifier(press)
            let timestamp = resolvedTimestamp(for: press)

            if activeSeekPressID == pressID {
                let directionForward = activeSeekIsForward
                activeSeekPressID = nil
                consumedPressIDs.remove(pressID)
                onSeekPressEnded?(directionForward, timestamp)
            } else if pendingSelectPressID == pressID {
                pendingSelectPressID = nil
                consumedPressIDs.remove(pressID)
                if isFocusCatchingEnabled {
                    onRevealOverlay?()
                }
            } else if consumedPressIDs.remove(pressID) != nil {
                continue
            } else {
                unhandled.insert(press)
            }
        }

        if !unhandled.isEmpty {
            super.pressesEnded(unhandled, with: event)
        }
    }

    public override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled: Set<UIPress> = []

        for press in presses {
            let pressID = ObjectIdentifier(press)

            if activeSeekPressID == pressID {
                let directionForward = activeSeekIsForward
                activeSeekPressID = nil
                consumedPressIDs.remove(pressID)
                onSeekPressCancelled?(directionForward)
            } else if pendingSelectPressID == pressID {
                pendingSelectPressID = nil
                consumedPressIDs.remove(pressID)
            } else if consumedPressIDs.remove(pressID) != nil {
                continue
            } else {
                unhandled.insert(press)
            }
        }

        if !unhandled.isEmpty {
            super.pressesCancelled(unhandled, with: event)
        }
    }

    private func resolvedTimestamp(for press: UIPress) -> TimeInterval {
        press.timestamp > 0 ? press.timestamp : ProcessInfo.processInfo.systemUptime
    }
}
