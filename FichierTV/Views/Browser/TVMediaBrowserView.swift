//
//  TVMediaBrowserView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Browser view presenting a media source's contents in either a 4-column grid or a vertical list.
///
/// Features focusable Grid/List layout switching (persisted per source), sort dialog restricted to supported keys,
/// paginated loading with thumbnail cancellation, initial first-item focus, and focus restoration when returning from viewers.
public struct TVMediaBrowserView: View {
    public let source: any MediaSource
    public let folder: MediaSourceItem?

    @State private var viewModel: TVBrowserViewModel
    @State private var showingSortDialog: Bool = false
    @FocusState private var focusedItemID: String?
    @State private var hasAppliedInitialFocus: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(source: any MediaSource, folder: MediaSourceItem?) {
        self.source = source
        self.folder = folder
        _viewModel = State(wrappedValue: TVBrowserViewModel(source: source, folder: folder))
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                TVErrorStateView(
                    message: error,
                    onRetry: {
                        Task { await viewModel.loadInitial(force: true) }
                    }
                )
            } else if viewModel.items.isEmpty {
                TVEmptyStateView(
                    isShares: source.preferredLayout == .list,
                    onBack: { dismiss() }
                )
            } else {
                VStack(spacing: 0) {
                    browserControlsBar
                        .focusSection()

                    contentLayout
                        .focusSection()
                }
            }
        }
        .navigationTitle(folder?.name ?? source.displayName)
        .confirmationDialog("Sort By", isPresented: $showingSortDialog, titleVisibility: .visible) {
            ForEach(orderedSortKeys, id: \.self) { key in
                Button {
                    viewModel.applySort(key: key)
                } label: {
                    Text(
                        viewModel.selectedSortKey == key
                            ? "✓ \(key.displayTitle)"
                            : key.displayTitle
                    )
                }
            }

            Button {
                viewModel.toggleSortOrder()
            } label: {
                Text(
                    viewModel.selectedSortOrder == .ascending
                        ? "Order: Ascending ↑ (Switch to Descending ↓)"
                        : "Order: Descending ↓ (Switch to Ascending ↑)"
                )
            }

            Button("Cancel", role: .cancel) {}
        }
        .defaultFocus($focusedItemID, viewModel.firstItemID)
        .onChange(of: viewModel.firstItemID) { _, newFirstID in
            if !hasAppliedInitialFocus, let newFirstID {
                hasAppliedInitialFocus = true
                if focusedItemID == nil {
                    focusedItemID = newFirstID
                }
            }
        }
        .task {
            if viewModel.items.isEmpty {
                await viewModel.loadInitial()
            } else {
                await viewModel.refreshSavedLayout()
                await viewModel.refreshSavedSortPreference()
            }
            if !hasAppliedInitialFocus, let firstID = viewModel.firstItemID {
                hasAppliedInitialFocus = true
                if focusedItemID == nil {
                    focusedItemID = firstID
                }
            }
        }
    }

    // MARK: - Layouts

    @ViewBuilder
    private var contentLayout: some View {
        Group {
            switch viewModel.selectedLayout {
            case .grid:
                gridLayout
            case .list:
                listLayout
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: viewModel.selectedLayout)
    }

    @ViewBuilder
    private var gridLayout: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 40), count: 4),
                spacing: 40
            ) {
                ForEach(viewModel.items) { item in
                    NavigationLink(value: destination(for: item)) {
                        TVMediaGridItemView(item: item)
                    }
                    .buttonStyle(.card)
                    .focused($focusedItemID, equals: item.id)
                    .onAppear {
                        viewModel.onItemAppear(item)
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 20)
            .padding(.bottom, 48)
        }
    }

    @ViewBuilder
    private var listLayout: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.items) { item in
                    NavigationLink(value: destination(for: item)) {
                        TVMediaListRowView(item: item)
                    }
                    .buttonStyle(.card)
                    .focused($focusedItemID, equals: item.id)
                    .onAppear {
                        viewModel.onItemAppear(item)
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        ProgressView("Loading items...")
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Focusable Browser Controls Bar

    @ViewBuilder
    private var browserControlsBar: some View {
        HStack(spacing: 20) {
            gridLayoutButton
            listLayoutButton
            sortOptionsButton

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("\(viewModel.items.count) \(viewModel.items.count == 1 ? "item" : "items")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 60)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var gridLayoutButton: some View {
        Button {
            viewModel.setLayout(.grid)
        } label: {
            Label("Grid", systemImage: "square.grid.2x2")
        }
        .buttonStyle(TVControlButtonStyle(isSelected: viewModel.selectedLayout == .grid))
        .accessibilityLabel("Grid layout")
        .accessibilityAddTraits(viewModel.selectedLayout == .grid ? .isSelected : [])
        .accessibilityIdentifier("browser_layout_grid_button")
    }

    @ViewBuilder
    private var listLayoutButton: some View {
        Button {
            viewModel.setLayout(.list)
        } label: {
            Label("List", systemImage: "list.bullet")
        }
        .buttonStyle(TVControlButtonStyle(isSelected: viewModel.selectedLayout == .list))
        .accessibilityLabel("List layout")
        .accessibilityAddTraits(viewModel.selectedLayout == .list ? .isSelected : [])
        .accessibilityIdentifier("browser_layout_list_button")
    }

    @ViewBuilder
    private var sortOptionsButton: some View {
        Button {
            showingSortDialog = true
        } label: {
            Label(
                "Sort: \(viewModel.selectedSortKey.displayTitle)",
                systemImage: viewModel.selectedSortOrder == .ascending ? "arrow.up" : "arrow.down"
            )
        }
        .buttonStyle(TVControlButtonStyle(isSelected: false))
        .accessibilityLabel("Sort options")
        .accessibilityValue(
            "\(viewModel.selectedSortKey.displayTitle), \(viewModel.selectedSortOrder == .ascending ? "ascending" : "descending")"
        )
        .accessibilityIdentifier("browser_sort_button")
    }

    private var orderedSortKeys: [MediaSortKey] {
        [MediaSortKey.name, .date, .size, .type].filter { source.supportedSortKeys.contains($0) }
    }

    // MARK: - Destination Routing

    private func destination(for item: MediaSourceItem) -> TVNavigationDestination {
        switch item.type {
        case .folder:
            return .browser(sourceID: source.id, folder: item)
        case .image:
            return .imageViewer(
                item: item,
                context: viewModel.items,
                pagination: viewModel.paginationContext
            )
        case .video:
            return .videoPlayer(item: item, context: viewModel.items)
        }
    }
}
