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

    @State private var viewModel: TVBrowserViewModel?
    @State private var showingSortDialog: Bool = false
    @FocusState private var focusedItemID: String?
    @State private var hasAppliedInitialFocus: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(source: any MediaSource, folder: MediaSourceItem?) {
        self.source = source
        self.folder = folder
        _viewModel = State(initialValue: nil)
    }

    init(viewModel: TVBrowserViewModel) {
        self.source = viewModel.source
        self.folder = viewModel.folder
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        Group {
            if let viewModel {
                browserStateContent(viewModel: viewModel)
            } else {
                loadingView
            }
        }
        .navigationTitle(folder?.name ?? source.displayName)
        .defaultFocus($focusedItemID, viewModel?.firstItemID)
        .onChange(of: viewModel?.firstItemID) { _, newFirstID in
            if !hasAppliedInitialFocus, let newFirstID {
                hasAppliedInitialFocus = true
                if focusedItemID == nil {
                    focusedItemID = newFirstID
                }
            }
        }
        .task(id: browserIdentity) {
            let activeViewModel = resolveViewModel()
            if activeViewModel.items.isEmpty {
                await activeViewModel.loadInitial()
            } else {
                await activeViewModel.refreshSavedLayout()
                await activeViewModel.refreshSavedSortPreference()
            }
            if !hasAppliedInitialFocus, let firstID = activeViewModel.firstItemID {
                hasAppliedInitialFocus = true
                if focusedItemID == nil {
                    focusedItemID = firstID
                }
            }
        }
    }

    // MARK: - View Model Lifecycle

    private var browserIdentity: String {
        "\(source.id)|\(folder?.id ?? "")|\(folder?.path ?? "")"
    }

    private func resolveViewModel() -> TVBrowserViewModel {
        if let existing = viewModel,
           existing.source.id == source.id,
           existing.folder?.id == folder?.id,
           existing.folder?.path == folder?.path {
            return existing
        }
        hasAppliedInitialFocus = false
        focusedItemID = nil
        showingSortDialog = false
        let created = TVBrowserViewModel(source: source, folder: folder)
        viewModel = created
        return created
    }

    // MARK: - Content States

    @ViewBuilder
    private func browserStateContent(viewModel: TVBrowserViewModel) -> some View {
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
                    browserControlsBar(viewModel: viewModel)
                        .focusSection()

                    contentLayout(viewModel: viewModel)
                        .focusSection()
                }
            }
        }
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
    }

    // MARK: - Layouts

    @ViewBuilder
    private func contentLayout(viewModel: TVBrowserViewModel) -> some View {
        Group {
            switch viewModel.selectedLayout {
            case .grid:
                gridLayout(viewModel: viewModel)
            case .list:
                listLayout(viewModel: viewModel)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: viewModel.selectedLayout)
    }

    @ViewBuilder
    private func gridLayout(viewModel: TVBrowserViewModel) -> some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 40), count: 4),
                spacing: 40
            ) {
                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: destination(for: item, in: viewModel)) {
                        TVMediaGridItemView(item: item)
                    }
                    .buttonStyle(.card)
                    .focused($focusedItemID, equals: item.id)
                    .onAppear {
                        viewModel.onItemAppear(at: index)
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 20)
            .padding(.bottom, 48)
        }
    }

    @ViewBuilder
    private func listLayout(viewModel: TVBrowserViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: destination(for: item, in: viewModel)) {
                        TVMediaListRowView(item: item)
                    }
                    .buttonStyle(.card)
                    .focused($focusedItemID, equals: item.id)
                    .onAppear {
                        viewModel.onItemAppear(at: index)
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
    private func browserControlsBar(viewModel: TVBrowserViewModel) -> some View {
        HStack(spacing: 20) {
            gridLayoutButton(viewModel: viewModel)
            listLayoutButton(viewModel: viewModel)
            sortOptionsButton(viewModel: viewModel)

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
    private func gridLayoutButton(viewModel: TVBrowserViewModel) -> some View {
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
    private func listLayoutButton(viewModel: TVBrowserViewModel) -> some View {
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
    private func sortOptionsButton(viewModel: TVBrowserViewModel) -> some View {
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

    private func destination(for item: MediaSourceItem, in viewModel: TVBrowserViewModel) -> TVNavigationDestination {
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
