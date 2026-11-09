//
//  StubMediaSourceResolver.swift
//  FichierTVTests
//
//

import Foundation
import FichierKit

actor StubMediaSourceResolver: MediaSourceResolverProtocol {
    private var sources: [String: any MediaSource]
    private(set) var invalidatedIDs: [String] = []

    init(sources: [String: any MediaSource] = [:]) {
        self.sources = sources
    }

    func resolve(sourceID: String) async -> (any MediaSource)? {
        sources[sourceID]
    }

    func invalidateSource(id: String) async {
        invalidatedIDs.append(id)
        sources.removeValue(forKey: id)
    }
}
