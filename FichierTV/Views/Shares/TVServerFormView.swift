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
            Section("Discovered Servers (Bonjour)") {
                if viewModel.discovery.isScanning && viewModel.discovery.discoveredHosts.isEmpty {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Searching local network...")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Searching local network for SMB servers")
                } else if viewModel.discovery.discoveredHosts.isEmpty {
                    Text("No SMB servers found on the local network.")
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
                                        Text("Resolving address...")
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
                            "\(host.name), \(host.resolvedHost ?? "resolving address")"
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
                        Label("Rescan Local Network", systemImage: "arrow.clockwise")
                        Spacer()
                        if viewModel.discovery.isScanning {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isSaving)
                .accessibilityHint("Scans the local network for Bonjour SMB servers")
            }

            Section("Server Information") {
                TextField("Server Name (e.g. Mac mini)", text: $viewModel.model.hostname)
                    .textContentType(.name)

                TextField("Host Address or IP (e.g. 192.168.1.50)", text: $viewModel.model.host)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
            }

            Section("Authentication") {
                TextField("Username", text: $viewModel.model.username)
                    .textContentType(.username)
                    .autocorrectionDisabled()

                SecureField("Password", text: $viewModel.model.password)
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
                            Text("Verifying Connection & Shares...")
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
                Button("Cancel") {
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
