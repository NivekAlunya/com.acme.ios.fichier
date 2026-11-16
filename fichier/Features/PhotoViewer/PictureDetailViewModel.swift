//
//  PictureDetailViewModel.swift
//  fichier
//

import Foundation
import Observation
import UIKit
import FichierKit

/// ViewModel managing photo browsing, slideshow state, image/EXIF loading state,
/// and HUD controls for ``PictureDetailView``.
@Observable
@MainActor
final class PictureDetailViewModel {
    // MARK: - Dependencies

    let manager: StorageLocationManager
    let pictures: [MediaItem]
    let initialItem: MediaItem

    // MARK: - Presentation & Slideshow State

    var currentItem: MediaItem
    var isPlayingSlideshow: Bool
    var slideDirection: SlideDirection = .forward
    var showControls = true

    // MARK: - Media & Metadata State

    var currentImage: UIImage?
    var slideImageCache: [String: UIImage] = [:]
    var activeMetadata: PictureEXIFData?
    var showingInfoSheet = false
    var saveStatusMessage: String?
    var isSaving = false

    // MARK: - Derived State

    var currentIndex: Int {
        pictures.firstIndex(where: { $0.id == currentItem.id }) ?? 0
    }

    // MARK: - Initialization

    init(
        manager: StorageLocationManager,
        pictures: [MediaItem],
        initialItem: MediaItem,
        autoStartSlideshow: Bool = false
    ) {
        self.manager = manager
        let photos = pictures.filter(\.isImage)
        self.pictures = photos.isEmpty ? [initialItem] : photos
        self.initialItem = initialItem
        self.currentItem = initialItem
        self.isPlayingSlideshow = autoStartSlideshow
    }

    // MARK: - Actions

    func advanceToNext() {
        guard !pictures.isEmpty else { return }
        slideDirection = .forward
        let nextIndex = (currentIndex + 1) % pictures.count
        currentItem = pictures[nextIndex]
    }

    func goToPrevious() {
        guard !pictures.isEmpty else { return }
        slideDirection = .backward
        let prevIndex = (currentIndex - 1 + pictures.count) % pictures.count
        currentItem = pictures[prevIndex]
    }

    func toggleSlideshow() {
        isPlayingSlideshow.toggle()
    }

    func toggleControls() {
        showControls.toggle()
    }
}
