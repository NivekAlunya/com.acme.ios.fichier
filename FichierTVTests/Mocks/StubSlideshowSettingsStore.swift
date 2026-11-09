//
//  StubSlideshowSettingsStore.swift
//  FichierTVTests
//
//

import Foundation
import FichierKit

actor StubSlideshowSettingsStore: SlideshowSettingsStoreProtocol {
    private var interval: TimeInterval
    private var style: SlideshowTransitionStyle

    init(interval: TimeInterval = 4.0, style: SlideshowTransitionStyle = .slide) {
        self.interval = interval
        self.style = style
    }

    func loadInterval() async -> TimeInterval {
        interval
    }

    func saveInterval(_ interval: TimeInterval) async {
        self.interval = interval
    }

    func loadTransitionStyle() async -> SlideshowTransitionStyle {
        style
    }

    func saveTransitionStyle(_ style: SlideshowTransitionStyle) async {
        self.style = style
    }
}
