//
//  TVSharesRootView.swift
//  FichierTV
//
//

import SwiftUI
import FichierKit

/// Root entry view for Shares, displaying saved SMB servers as cards and a trailing Add Server card.
public struct TVSharesRootView: View {
    @State private var viewModel: TVSharesViewModel
    @State private var editingServer: SavedSMBConnection?

    public init() {
        // Note: SwiftUI view structs are transient and re-evaluated during parent updates.
        // While State(wrappedValue:) evaluates on every init, @State retains only the
        // original state object across renders and discards transient allocations.
        _viewModel = State(wrappedValue: TVSharesViewModel())
    }

    init(viewModel: TVSharesViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(viewModel.serverCards) { card in
                        NavigationLink(value: TVNavigationDestination.browser(sourceID: card.id, folder: nil)) {
                            TVServerCardView(card: card)
                        }
                        .buttonStyle(.card)
                        .contextMenu {
                            Button("Edit Server") {
                                editingServer = card.connection
                            }
                            Button("Remove Server", role: .destructive) {
                                Task {
                                    await viewModel.removeServer(card.connection)
                                }
                            }
                        }
                        .onPlayPauseCommand {
                            viewModel.selectedServerForAction = card
                            viewModel.showingActionSheet = true
                        }
                    }

                    NavigationLink(value: TVNavigationDestination.addServer) {
                        TVAddServerCardView()
                    }
                    .buttonStyle(.card)
                }
                .padding(.horizontal, 60)
                .padding(.top, 20)
                .padding(.bottom, 36)
            }
            .frame(height: 280)
            .scrollClipDisabled()
            .focusSection()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationDestination(item: $editingServer) { server in
            TVServerFormView(mode: .edit(server))
        }
        .confirmationDialog(
            viewModel.selectedServerForAction?.name ?? "Server Actions",
            isPresented: $viewModel.showingActionSheet,
            titleVisibility: .visible
        ) {
            if let server = viewModel.selectedServerForAction?.connection {
                Button("Edit Server") {
                    editingServer = server
                }
                Button("Remove Server", role: .destructive) {
                    Task {
                        await viewModel.removeServer(server)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            Task {
                await viewModel.loadServers()
            }
        }
    }

    @ViewBuilder
    private var headerBar: some View {
        HStack(spacing: 16) {
            Text("SMB Servers")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 60)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }
}
