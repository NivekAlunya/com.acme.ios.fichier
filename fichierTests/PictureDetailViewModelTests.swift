//
//  PictureDetailViewModelTests.swift
//  fichierTests
//

import Foundation
import Testing
import UIKit
import FichierKit
@testable import Fichier

@Suite("PictureDetailViewModel")
@MainActor
struct PictureDetailViewModelTests {
    private func makePhoto(_ name: String) -> MediaItem {
        MediaItem(name: name, path: "/\(name)", isDirectory: false, size: 100)
    }

    @Test("init filters non-image items and falls back to initialItem when none are images")
    func initFiltersImages() {
        let photo = makePhoto("a.jpg")
        let video = makePhoto("b.mp4")

        let vmWithPhotos = PictureDetailViewModel(
            manager: StorageLocationManager(),
            pictures: [photo, video],
            initialItem: photo
        )
        #expect(vmWithPhotos.pictures.map(\.name) == ["a.jpg"])

        let vmFallback = PictureDetailViewModel(
            manager: StorageLocationManager(),
            pictures: [video],
            initialItem: video
        )
        #expect(vmFallback.pictures.map(\.name) == ["b.mp4"])
    }

    @Test("advanceToNext and goToPrevious wrap around and update slideDirection")
    func navigationWrapAround() {
        let first = makePhoto("1.jpg")
        let second = makePhoto("2.jpg")
        let viewModel = PictureDetailViewModel(
            manager: StorageLocationManager(),
            pictures: [first, second],
            initialItem: first
        )

        #expect(viewModel.currentIndex == 0)

        viewModel.advanceToNext()
        #expect(viewModel.currentItem.name == "2.jpg")
        #expect(viewModel.slideDirection == .forward)

        viewModel.advanceToNext()
        #expect(viewModel.currentItem.name == "1.jpg")

        viewModel.goToPrevious()
        #expect(viewModel.currentItem.name == "2.jpg")
        #expect(viewModel.slideDirection == .backward)
    }

    @Test("toggleSlideshow and toggleControls flip their flags")
    func toggles() {
        let photo = makePhoto("1.jpg")
        let viewModel = PictureDetailViewModel(
            manager: StorageLocationManager(),
            pictures: [photo],
            initialItem: photo,
            autoStartSlideshow: false
        )

        #expect(!viewModel.isPlayingSlideshow)
        viewModel.toggleSlideshow()
        #expect(viewModel.isPlayingSlideshow)

        #expect(viewModel.showControls)
        viewModel.toggleControls()
        #expect(!viewModel.showControls)

        // Pausing slideshow restores controls
        viewModel.toggleSlideshow()
        #expect(!viewModel.isPlayingSlideshow)
        #expect(viewModel.showControls)
    }

    @Test("autoStartSlideshow initializes with isPlayingSlideshow true")
    func autoStartSlideshowInitialState() {
        let photo = makePhoto("1.jpg")
        let viewModel = PictureDetailViewModel(
            manager: StorageLocationManager(),
            pictures: [photo],
            initialItem: photo,
            autoStartSlideshow: true
        )

        #expect(viewModel.isPlayingSlideshow)
        #expect(viewModel.showControls)
    }

    @Test("SlideImageCache stores, retrieves, and removes images cleanly")
    func slideImageCacheOperations() {
        let cache = SlideImageCache()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let image = renderer.image { _ in }

        cache["item1"] = image
        #expect(cache["item1"] != nil)

        cache["item1"] = nil
        #expect(cache["item1"] == nil)

        cache["item2"] = image
        cache.removeAll()
        #expect(cache["item2"] == nil)
    }
}
