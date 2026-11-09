//
//  TVRootMediaBrowserView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Root `NavigationStack` container providing a top navigation bar for Photos and Shares.
///
/// Ensures Siri Remote Menu navigation pops within the stack rather than immediately exiting the app,
/// supports focused section restoration, and routes to browser screens and media viewers.
public struct TVRootMediaBrowserView: View {
    @State private var selectedSection: TVRootSection = .photos
    @State private var navigationPath = NavigationPath()
    @FocusState private var isNavigationBarFocused: Bool

    public init() {}

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                switch selectedSection {
                case .photos:
                    TVPhotosRootView()
                case .shares:
                    TVSharesRootView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Source", selection: $selectedSection) {
                        ForEach(TVRootSection.allCases) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .focused($isNavigationBarFocused)
                }
            }
            .navigationDestination(for: TVNavigationDestination.self) { destination in
                switch destination {
                case .browser(let sourceID, let folder):
                    TVBrowserDestinationView(sourceID: sourceID, folder: folder)
                case .imageViewer(let item, let context, let pagination):
                    TVImageViewerView(initialItem: item, items: context, paginationContext: pagination)
                case .videoPlayer(let item, let context):
                    TVVideoPlayerView(initialItem: item, videos: context)
                case .addServer:
                    TVServerFormView(mode: .add)
                case .editServer(let server):
                    TVServerFormView(mode: .edit(server))
                }
            }
        }
    }
}
