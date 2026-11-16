//
//  LocationsSidebarViewModel.swift
//  fichier
//

import Foundation
import Observation
import FichierKit

/// ViewModel managing folder-picker presentation and import error state
/// for ``LocationsSidebarView``.
@Observable
@MainActor
final class LocationsSidebarViewModel {
    // MARK: - Dependencies

    let manager: StorageLocationManager

    // MARK: - Navigation Items
    
    /// Flattened collection of storage locations and discovered SMB shares for sidebar rendering.
    var sidebarItems: [SidebarItem] {
        var items: [SidebarItem] = []
        for location in manager.allLocations {
            items.append(.location(location))
            if location.kind == .smb,
               manager.isConnected,
               manager.currentLocation?.id == location.id {
                for share in manager.serverShares {
                    items.append(.share(share))
                }
            }
        }
        return items
    }

    // MARK: - Presentation & Error State

    var showingFolderPicker = false
    var folderPickerErrorMessage: String?
    var showingFolderErrorAlert = false

    // MARK: - Initialization

    init(manager: StorageLocationManager) {
        self.manager = manager
    }

    // MARK: - Actions

    func presentFolderPicker() {
        showingFolderPicker = true
    }

    func handleFolderImportFailure(_ message: String) {
        folderPickerErrorMessage = message
        showingFolderErrorAlert = true
    }

    func dismissFolderError() {
        folderPickerErrorMessage = nil
        showingFolderErrorAlert = false
    }
}
