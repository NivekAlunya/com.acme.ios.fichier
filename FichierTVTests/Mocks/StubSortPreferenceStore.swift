//
//  StubSortPreferenceStore.swift
//  FichierTVTests
//
//

import Foundation
import FichierKit

actor StubSortPreferenceStore: MediaSortPreferenceStoreProtocol {
    private var storage: [String: MediaSortPreference]

    init(initialPreferences: [String: MediaSortPreference] = [:]) {
        self.storage = initialPreferences
    }

    func savePreference(_ preference: MediaSortPreference, for sourceID: String) async {
        storage[sourceID] = preference
    }

    func preference(for sourceID: String) async -> MediaSortPreference? {
        storage[sourceID]
    }
}
