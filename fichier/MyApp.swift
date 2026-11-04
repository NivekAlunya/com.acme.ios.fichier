//
//  MyApp.swift
//  fichier
//

import SwiftUI

/// Main entry point for the Fichier application.
///
/// Launches the primary `WindowGroup` scene embedding `RootSMBView`, the root visual coordinator.
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RootSMBView()
        }
    }
}
