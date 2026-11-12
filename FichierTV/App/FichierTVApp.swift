//
//  FichierTVApp.swift
//  FichierTV
//

import SwiftUI
import Wappn
import FichierKit

/// tvOS application entry point.
@main
public struct FichierTVApp: App {
    public init() {
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

    public var body: some Scene {
        WindowGroup {
            TVRootMediaBrowserView()
        }
    }
}
