//
//  PDFDetailViewModel.swift
//  fichier
//

#if !os(tvOS)
import Foundation
import Observation
import PDFKit
import FichierKit

/// ViewModel managing PDF document loading, page/spread navigation,
/// download progress, and HUD state for ``PDFDetailView``.
@Observable
@MainActor
final class PDFDetailViewModel {
    // MARK: - Dependencies

    let manager: StorageLocationManager
    let documents: [MediaItem]

    // MARK: - Document & Loading State

    var currentItem: MediaItem
    var document: PDFDocument?
    var localFileURL: URL?
    var isLoading = true
    var bytesReceived: Int64 = 0
    var totalBytes: Int64 = 0
    var lastReportedBytes: Int64 = 0
    var errorMessage: String?
    var reloadAttempt = 0

    // MARK: - Navigation & HUD State

    var showControls = true
    var currentPage = 1
    var endVisiblePage = 1
    var totalPages = 1
    var currentSpreadIndex = 0
    var activePDFView: PDFView?
    var coordinator: PDFKitCoordinator?

    // MARK: - Initialization

    init(
        manager: StorageLocationManager,
        documents: [MediaItem],
        initialItem: MediaItem
    ) {
        self.manager = manager
        self.documents = documents
        self.currentItem = initialItem
    }

    // MARK: - Actions

    func toggleControls() {
        showControls.toggle()
    }

    func retryLoad() {
        errorMessage = nil
        isLoading = true
        reloadAttempt += 1
    }

    func resetForNewDocument() {
        document = nil
        localFileURL = nil
        isLoading = true
        bytesReceived = 0
        totalBytes = 0
        lastReportedBytes = 0
        errorMessage = nil
        currentPage = 1
        endVisiblePage = 1
        totalPages = 1
        currentSpreadIndex = 0
    }
}
#endif
