//
//  TVServerFormView.swift
//  FichierTV
//
//

import SwiftUI
import FichierKit

/// Full-screen form on tvOS for adding or editing an SMB server connection with Bonjour discovery.
public struct TVServerFormView: View {
    @State private var viewModel: TVServerFormViewModel
    @Environment(\.dismiss) private var dismiss

    public init(
        mode: TVServerFormMode,
        store: any SMBServerStoreProtocol = DefaultSMBServerStore.shared,
        validator: any SMBConnectionValidatorProtocol = DefaultSMBConnectionValidator.shared,
        discovery: (any SMBHostDiscoveryProtocol)? = nil,
        resolver: any MediaSourceResolverProtocol = DefaultMediaSourceResolver.shared
    ) {
        // Note: SwiftUI view structs are transient and re-evaluated during parent updates.
        // While State(wrappedValue:) evaluates on every init, @State retains only the
        // original state object across renders and discards transient allocations.
        _viewModel = State(wrappedValue: TVServerFormViewModel(
            mode: mode,
            store: store,
            validator: validator,
            discovery: discovery,
            resolver: resolver
        ))
    }

    public var body: some View {
        Form {
            Section(.Strings.tvServerSectionBonjour) {
                if viewModel.discovery.isScanning && viewModel.discovery.discoveredHosts.isEmpty {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text(.Strings.tvServerSearchingLocalNetwork)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(.Strings.tvServerSearchingAccessibility))
                } else if viewModel.discovery.discoveredHosts.isEmpty {
                    Text(.Strings.tvServerNoServersFound)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.discovery.discoveredHosts) { host in
                        Button {
                            viewModel.selectDiscoveredHost(host)
                        } label: {
                            HStack(spacing: 20) {
                                Image(systemName: "server.rack")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(host.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    if let resolvedHost = host.resolvedHost {
                                        Text(resolvedHost)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(.Strings.tvServerResolvingAddress)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if viewModel.isSelectedDiscoveredHost(host) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .disabled(host.resolvedHost == nil || viewModel.isSaving)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(host.name), \(host.resolvedHost ?? String(localized: .Strings.tvServerResolvingAddress))"
                        )
                        .accessibilityHint(
                            viewModel.isSelectedDiscoveredHost(host)
                                ? "Currently selected server"
                                : "Select to fill server name and IP address"
                        )
                    }
                }

                Button {
                    viewModel.rescanNetwork()
                } label: {
                    HStack {
                        Label(.Strings.tvServerRescanButton, systemImage: "arrow.clockwise")
                        Spacer()
                        if viewModel.discovery.isScanning {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isSaving)
                .accessibilityHint(Text(.Strings.tvServerRescanAccessibilityHint))
            }

            Section(.Strings.tvServerSectionServerInfo) {
                TextField(String(localized: .Strings.connectionFieldServerName), text: $viewModel.model.hostname)
                    .textContentType(.name)

                TextField(String(localized: .Strings.connectionFieldHostAddress), text: $viewModel.model.host)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
            }

            Section(.Strings.tvServerSectionAuth) {
                TextField(String(localized: .Strings.connectionFieldMacUsername), text: $viewModel.model.username)
                    .textContentType(.username)
                    .autocorrectionDisabled()

                SecureField(String(localized: .Strings.connectionFieldMacPassword), text: $viewModel.model.password)
                    .textContentType(.password)
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Button(action: submit) {
                    HStack(spacing: 16) {
                        Spacer()
                        if viewModel.isSaving {
                            ProgressView()
                            Text(.Strings.tvServerVerifyingConnection)
                                .fontWeight(.semibold)
                        } else {
                            Text(viewModel.modeTitle)
                                .fontWeight(.bold)
                        }
                        Spacer()
                    }
                }
                .disabled(!viewModel.isValid || viewModel.isSaving)
            }
        }
        .navigationTitle(viewModel.modeTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(.Strings.commonCancel) {
                    dismiss()
                }
            }
        }
        .task {
            await viewModel.loadInitialState()
        }
        .onDisappear {
            viewModel.stopDiscovery()
        }
    }

    private func submit() {
        Task {
            if await viewModel.save() {
                dismiss()
            }
        }
    }
}
