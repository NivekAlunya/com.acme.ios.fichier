//
//  FichierTVApp.swift
//  FichierTV
//

import SwiftUI

/// tvOS application entry point.
@main
public struct FichierTVApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            TVRootMediaBrowserView()
        }
    }
}
