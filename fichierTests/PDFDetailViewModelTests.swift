//
//  PDFDetailViewModelTests.swift
//  fichierTests
//

import Foundation
import Testing
import FichierKit
@testable import fichier

@Suite("PDFDetailViewModel")
@MainActor
struct PDFDetailViewModelTests {
    private func makePDF(_ name: String) -> MediaItem {
        MediaItem(name: name, path: "/\(name)", isDirectory: false, size: 1024)
    }

    @Test("retryLoad clears errorMessage, sets isLoading, and increments reloadAttempt")
    func retryLoad() {
        let doc = makePDF("manual.pdf")
        let viewModel = PDFDetailViewModel(
            manager: StorageLocationManager(),
            documents: [doc],
            initialItem: doc
        )

        viewModel.errorMessage = "Network error"
        viewModel.isLoading = false

        viewModel.retryLoad()

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading)
        #expect(viewModel.reloadAttempt == 1)
    }

    @Test("resetForNewDocument resets progress, error, and page state")
    func resetForNewDocument() {
        let doc = makePDF("manual.pdf")
        let viewModel = PDFDetailViewModel(
            manager: StorageLocationManager(),
            documents: [doc],
            initialItem: doc
        )

        viewModel.isLoading = false
        viewModel.bytesReceived = 512
        viewModel.totalBytes = 1024
        viewModel.lastReportedBytes = 512
        viewModel.errorMessage = "Failed"
        viewModel.currentPage = 5
        viewModel.endVisiblePage = 6
        viewModel.totalPages = 20
        viewModel.currentSpreadIndex = 2

        viewModel.resetForNewDocument()

        #expect(viewModel.document == nil)
        #expect(viewModel.localFileURL == nil)
        #expect(viewModel.isLoading)
        #expect(viewModel.bytesReceived == 0)
        #expect(viewModel.totalBytes == 0)
        #expect(viewModel.lastReportedBytes == 0)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.currentPage == 1)
        #expect(viewModel.endVisiblePage == 1)
        #expect(viewModel.totalPages == 1)
        #expect(viewModel.currentSpreadIndex == 0)
    }

    @Test("toggleControls flips showControls")
    func toggleControls() {
        let doc = makePDF("manual.pdf")
        let viewModel = PDFDetailViewModel(
            manager: StorageLocationManager(),
            documents: [doc],
            initialItem: doc
        )

        #expect(viewModel.showControls)
        viewModel.toggleControls()
        #expect(!viewModel.showControls)
    }
}
