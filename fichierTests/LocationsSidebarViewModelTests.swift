//
//  LocationsSidebarViewModelTests.swift
//  fichierTests
//

import Testing
import FichierKit
@testable import fichier

@Suite("LocationsSidebarViewModel")
@MainActor
struct LocationsSidebarViewModelTests {
    @Test("presentFolderPicker sets showingFolderPicker")
    func presentFolderPicker() {
        let viewModel = LocationsSidebarViewModel(manager: StorageLocationManager())

        #expect(!viewModel.showingFolderPicker)
        viewModel.presentFolderPicker()
        #expect(viewModel.showingFolderPicker)
    }

    @Test("handleFolderImportFailure and dismissFolderError manage error alert state")
    func folderImportErrorLifecycle() {
        let viewModel = LocationsSidebarViewModel(manager: StorageLocationManager())

        viewModel.handleFolderImportFailure("Permission denied")
        #expect(viewModel.folderPickerErrorMessage == "Permission denied")
        #expect(viewModel.showingFolderErrorAlert)

        viewModel.dismissFolderError()
        #expect(viewModel.folderPickerErrorMessage == nil)
        #expect(!viewModel.showingFolderErrorAlert)
    }
}
