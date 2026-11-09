import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Thread-safe tactile haptic feedback dispatcher with graceful no-ops on tvOS and macOS.
public enum AppHapticFeedback: Sendable {
    /// Triggers light impact feedback for minor interactions (selection, toggle, tap).
    @MainActor
    public static func light() {
        #if canImport(UIKit) && !os(tvOS) && !os(watchOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    
    /// Triggers medium impact feedback for affirmative user actions (save, favorite, delete).
    @MainActor
    public static func medium() {
        #if canImport(UIKit) && !os(tvOS) && !os(watchOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    
    /// Triggers selection change feedback for pickers and scrubbers.
    @MainActor
    public static func selection() {
        #if canImport(UIKit) && !os(tvOS) && !os(watchOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
