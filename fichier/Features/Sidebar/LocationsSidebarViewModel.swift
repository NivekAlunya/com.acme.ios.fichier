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
        manager.allLocations.flatMap { location -> [SidebarItem] in
            var items: [SidebarItem] = [.location(location)]
            if location.kind == .smb,
               manager.isConnected,
               manager.currentLocation?.id == location.id {
                items.append(contentsOf: manager.serverShares.map(SidebarItem.share))
            }
            return items
        }
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
