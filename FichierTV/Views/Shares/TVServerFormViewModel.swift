//
//  TVServerFormViewModel.swift
//  FichierTV
//
//

import Foundation
import Observation
import FichierKit

/// Coordinates Bonjour server discovery, SMB credential validation, and persistence for `TVServerFormView`.
@Observable
@MainActor
public final class TVServerFormViewModel {
    public let mode: TVServerFormMode
    public var model = SMBServerFormModel()
    public let discovery: any SMBHostDiscoveryProtocol

    private let store: any SMBServerStoreProtocol
    private let validator: any SMBConnectionValidatorProtocol
    private let resolver: any MediaSourceResolverProtocol

    public var isValid: Bool { model.isValid }
    public var isSaving: Bool { model.isSaving }
    public var errorMessage: String? { model.errorMessage ?? discovery.errorMessage }

    public var modeTitle: String {
        switch mode {
        case .add:
            return "Add Server"
        case .edit:
            return "Edit Server"
        }
    }

    public init(
        mode: TVServerFormMode,
        store: any SMBServerStoreProtocol = DefaultSMBServerStore.shared,
        validator: any SMBConnectionValidatorProtocol = DefaultSMBConnectionValidator.shared,
        discovery: (any SMBHostDiscoveryProtocol)? = nil,
        resolver: any MediaSourceResolverProtocol = DefaultMediaSourceResolver.shared
    ) {
        self.mode = mode
        self.store = store
        self.validator = validator
        self.discovery = discovery ?? SMBHostDiscovery()
        self.resolver = resolver
    }

    /// Loads existing server details (when editing) and starts Bonjour `_smb._tcp` discovery.
    public func loadInitialState() async {
        if case .edit(let server) = mode {
            let existingPassword = await store.password(for: server) ?? ""
            model.populate(from: server, existingPassword: existingPassword)
        }
        discovery.startDiscovery()
    }

    /// Stops any active Bonjour scan and resolution sockets.
    public func stopDiscovery() {
        discovery.stopDiscovery()
    }

    /// Restarts Bonjour discovery on demand.
    public func rescanNetwork() {
        model.errorMessage = nil
        discovery.startDiscovery()
    }

    /// Pre-fills form inputs from a resolved Bonjour host.
    public func selectDiscoveredHost(_ host: DiscoveredHost) {
        guard let resolvedHost = host.resolvedHost?.trimmingCharacters(in: .whitespacesAndNewlines),
              !resolvedHost.isEmpty else {
            return
        }

        model.host = resolvedHost
        if case .add = mode {
            model.hostname = host.name
        } else if model.hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.hostname = host.name
        }
        model.errorMessage = nil
    }

    /// Returns whether the discovered host matches the currently entered host address.
    public func isSelectedDiscoveredHost(_ host: DiscoveredHost) -> Bool {
        let currentHost = model.normalizedHost
        guard !currentHost.isEmpty, let resolvedHost = host.resolvedHost else {
            return false
        }
        return resolvedHost == currentHost
    }

    /// Verifies SMB connectivity and share enumeration before saving the server configuration.
    ///
    /// - Returns: `true` if verification and persistence succeeded.
    @discardableResult
    public func save() async -> Bool {
        guard model.isValid, !model.isSaving else { return false }

        model.isSaving = true
        model.errorMessage = nil

        let connection = model.makeConnection()
        let pass = model.password

        do {
            _ = try await validator.validateAndListShares(for: connection, password: pass)
            try await store.saveServer(connection, password: pass)

            if case .edit(let previousServer) = mode {
                await resolver.invalidateSource(id: previousServer.id)
                if previousServer.id != connection.id {
                    try? await store.removeServer(previousServer)
                }
            }
            await resolver.invalidateSource(id: connection.id)

            model.isSaving = false
            return true
        } catch is CancellationError {
            model.isSaving = false
            return false
        } catch {
            model.errorMessage = error.localizedDescription
            model.isSaving = false
            return false
        }
    }
}
