//
//  StubLayoutPreferenceStore.swift
//  FichierTVTests
//
//

import Foundation
import FichierKit

actor StubLayoutPreferenceStore: MediaLayoutPreferenceStoreProtocol {
    private var storage: [String: MediaSourceLayout]

    init(initialLayouts: [String: MediaSourceLayout] = [:]) {
        self.storage = initialLayouts
    }

    func saveLayout(_ layout: MediaSourceLayout, for sourceID: String) async {
        storage[sourceID] = layout
    }

    func layout(for sourceID: String) async -> MediaSourceLayout? {
        storage[sourceID]
    }
}
