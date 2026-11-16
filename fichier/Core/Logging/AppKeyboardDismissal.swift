//
//  AppKeyboardDismissal.swift
//  fichier
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Safe software keyboard dismissal utility with platform-safe no-ops on tvOS.
public enum AppKeyboardDismissal: Sendable {
    /// Resigns first responder to dismiss the on-screen software keyboard.
    @MainActor
    public static func dismiss() {
        #if canImport(UIKit) && !os(tvOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }
}
