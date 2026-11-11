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
    init() {
        #if DEBUG
        // Must run first: archives last session's crash report and arms the crash handlers for this one.
        CrashReporting.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootSMBView()
        }
    }
}
