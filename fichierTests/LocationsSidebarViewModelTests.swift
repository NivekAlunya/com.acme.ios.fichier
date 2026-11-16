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

    @Test("sidebarItems contains only locations when disconnected")
    func sidebarItemsWhenDisconnected() {
        let manager = StorageLocationManager()
        let viewModel = LocationsSidebarViewModel(manager: manager)

        let items = viewModel.sidebarItems
        #expect(!items.isEmpty)
        for item in items {
            switch item {
            case .location:
                #expect(true)
            case .share:
                Issue.record("Should not contain shares when disconnected")
            }
        }
    }

    @Test("sidebarItems includes discovered shares under connected SMB location")
    func sidebarItemsWhenSMBConnected() async {
        let manager = StorageLocationManager()
        let server = SavedSMBConnection(host: "nas.local", username: "alice", lastConnected: Date(), hostname: "nas")
        let location = StorageLocation(smb: server)
        manager.currentLocation = location
        manager.isConnected = true
        
        let share1 = MediaItem(name: "Photos", path: "", type: .folder, shareName: "Photos", locationID: location.id)
        let share2 = MediaItem(name: "Videos", path: "", type: .folder, shareName: "Videos", locationID: location.id)
        manager.folderTree = [share1, share2]
        
        let viewModel = LocationsSidebarViewModel(manager: manager)
        let items = viewModel.sidebarItems
        
        let shareItems = items.compactMap { item -> MediaItem? in
            if case .share(let share) = item {
                return share
            }
            return nil
        }
        #expect(shareItems.count == 2)
        #expect(shareItems.map(\.name) == ["Photos", "Videos"])
        #expect(manager.selectedShare == nil)
        
        await manager.selectShare(share1)
        #expect(manager.selectedShare?.name == "Photos")
    }
}
