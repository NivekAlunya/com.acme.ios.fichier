//
//  StatusToastModifier.swift
//  fichier
//

import SwiftUI

/// View modifier displaying a high-contrast floating toast banner upon operation completion.
public struct StatusToastModifier: ViewModifier {
    /// Two-way binding to the transient message string. When non-nil, the toast is visible.
    @Binding public var message: String?
    
    /// SF Symbol icon name displayed at the leading edge.
    public var systemImage: String = "checkmark.circle.fill"
    
    /// Color of the leading symbol icon.
    public var iconColor: Color = .green
    
    public init(
        message: Binding<String?>,
        systemImage: String = "checkmark.circle.fill",
        iconColor: Color = .green
    ) {
        self._message = message
        self.systemImage = systemImage
        self.iconColor = iconColor
    }
    
    public func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    HStack(spacing: 8) {
                        Image(systemName: systemImage)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(iconColor)
                        
                        Text(message)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemBackground))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 5)
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(message)
                }
            }
            .animation(.snappy, value: message)
            #if !os(tvOS)
            .sensoryFeedback(.success, trigger: message) { _, new in new != nil }
            #endif
    }
}

extension View {
    /// Presents a transient high-contrast status toast pill at the top of the view.
    ///
    /// - Parameters:
    ///   - message: Binding to an optional status message.
    ///   - systemImage: SF Symbol icon name.
    ///   - iconColor: Tint color for the symbol.
    /// - Returns: A modified view displaying the toast overlay when `message` is non-nil.
    public func statusToast(
        message: Binding<String?>,
        systemImage: String = "checkmark.circle.fill",
        iconColor: Color = .green
    ) -> some View {
        modifier(StatusToastModifier(message: message, systemImage: systemImage, iconColor: iconColor))
    }
}
