//
//  View+MatchedTransitionSource.swift
//  fichier
//
//  Created on 2026-11-24.
//

import SwiftUI

extension View {
    /// Attaches a matched transition source when a zoom-transition namespace is provided.
    ///
    /// - Parameters:
    ///   - id: Stable identifier matching the presented detail view's `sourceID`.
    ///   - namespace: Optional namespace shared with the presenting container.
    @ViewBuilder
    func optionalMatchedTransitionSource<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID?
    ) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
