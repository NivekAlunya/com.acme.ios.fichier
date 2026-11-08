import SwiftUI

/// Semantic cross-platform color palette bridging platform differences between iOS, macOS, and tvOS.
public enum AppColor: Sendable {
    /// Adaptive secondary background color suitable for cards, rows, and containers.
    public static var secondarySystemBackground: Color {
        #if os(tvOS)
        Color(white: 0.18)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
    
    /// Adaptive primary background color for top-level canvas backgrounds.
    public static var systemBackground: Color {
        #if os(tvOS)
        Color.black
        #elseif os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
    
    /// Adaptive tertiary fill color suitable for subtle overlays and badge fills.
    public static var tertiarySystemFill: Color {
        #if os(tvOS)
        Color.white.opacity(0.12)
        #elseif os(macOS)
        Color(nsColor: .tertiaryLabelColor).opacity(0.15)
        #else
        Color(uiColor: .tertiarySystemFill)
        #endif
    }
}
