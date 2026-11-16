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
