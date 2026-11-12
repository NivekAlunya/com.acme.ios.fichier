//
//  FichierApp.swift
//  fichier
//

import SwiftUI
import Wappn
import FichierKit

/// Main entry point for the Fichier application.
///
/// Launches the primary `WindowGroup` scene embedding `RootSMBView`, the root visual coordinator.
@main
struct FichierApp: App {
    init() {
        // According to Apple's BSD Sockets & Multitasking documentation:
        // "By default, a SIGPIPE signal is sent to the process when a write to a socket or pipe fails
        // because the other end has closed the connection. The default action for SIGPIPE is to terminate
        // the process... To prevent SIGPIPE from terminating your application, set the signal handler
        // for SIGPIPE to SIG_IGN."
        Wappn.ignoreSigpipe()
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
