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
    @FocusState private var focusedTarget: TVBrowserFocusTarget?
    @State private var hasAppliedInitialFocus: Bool = false
    @State private var lastPlayPauseTimestamp: Date = .distantPast
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
        .fichierAtmosphericBackground()
        .navigationTitle(folder?.name ?? source.displayName)
        .defaultFocus($focusedTarget, viewModel?.firstItemID.map { .item($0) })
        .onChange(of: viewModel?.firstItemID) { _, newFirstID in
            if !hasAppliedInitialFocus, let newFirstID {
                hasAppliedInitialFocus = true
                if focusedTarget == nil {
                    focusedTarget = .item(newFirstID)
                }
            }
        }
        .onChange(of: MediaDetailStore.shared.revision) { _, _ in
            if viewModel?.selectedSortKey == .duration || viewModel?.selectedSortKey == .resolution {
                viewModel?.applyCurrentSortToItems()
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
                if focusedTarget == nil {
                    focusedTarget = .item(firstID)
                }
            }
        }
        .refreshable {
            await viewModel?.refreshCurrentFolder()
        }
        .onPlayPauseCommand {
            let now = Date()
            if now.timeIntervalSince(lastPlayPauseTimestamp) < 0.4 {
                viewModel?.toggleLayout()
            } else {
                focusedTarget = .optionsMenu
            }
            lastPlayPauseTimestamp = now
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
        focusedTarget = nil
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
                }
            }
        }
        .confirmationDialog(.Strings.galleryMenuSortBy, isPresented: $showingSortDialog, titleVisibility: .visible) {
            ForEach(orderedSortKeys, id: \.self) { key in
                Button {
                    viewModel.applySort(key: key)
                } label: {
                    Text(
                        viewModel.selectedSortKey == key
                            ? String(localized: .Strings.tvSortSelectedItemFormat(key.displayTitle))
                            : key.displayTitle
                    )
                }
            }

            Button {
                viewModel.toggleSortOrder()
            } label: {
                Text(
                    viewModel.selectedSortOrder == .ascending
                        ? .Strings.tvSortOrderAscendingToggle
                        : .Strings.tvSortOrderDescendingToggle
                )
            }

            Button(.Strings.commonCancel, role: .cancel) {}
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
                columns: Array(repeating: GridItem(.flexible(), spacing: 32), count: 6),
                spacing: 32
            ) {
                ForEach(viewModel.items) { item in
                    NavigationLink(value: destination(for: item, in: viewModel)) {
                        TVMediaGridItemView(item: item)
                    }
                    .buttonStyle(TVMediaCardButtonStyle())
                    .focused($focusedTarget, equals: .item(item.id))
                    .contextMenu {
                        layoutContextMenu(viewModel: viewModel)
                    }
                    .onAppear {
                        viewModel.onItemAppear(item: item)
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
                ForEach(viewModel.items) { item in
                    NavigationLink(value: destination(for: item, in: viewModel)) {
                        TVMediaListRowView(item: item)
                    }
                    .buttonStyle(TVMediaCardButtonStyle())
                    .focused($focusedTarget, equals: .item(item.id))
                    .contextMenu {
                        layoutContextMenu(viewModel: viewModel)
                    }
                    .onAppear {
                        viewModel.onItemAppear(item: item)
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private func layoutContextMenu(viewModel: TVBrowserViewModel) -> some View {
        Button {
            viewModel.toggleLayout()
        } label: {
            Label(
                viewModel.selectedLayout == .grid
                    ? String(localized: .Strings.tvMediaViewList)
                    : String(localized: .Strings.tvMediaViewGrid),
                systemImage: viewModel.selectedLayout == .grid
                    ? "list.bullet"
                    : "square.grid.2x2"
            )
        }

        Button {
            showingSortDialog = true
        } label: {
            Label(
                String(localized: .Strings.galleryMenuSortBy),
                systemImage: "arrow.up.arrow.down"
            )
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        ProgressView(.Strings.tvMediaLoadingItems)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Focusable Browser Controls Bar

    @ViewBuilder
    private func browserControlsBar(viewModel: TVBrowserViewModel) -> some View {
        HStack(spacing: 20) {
            browserOptionsMenu(viewModel: viewModel)

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(.Strings.tvMediaItemsCount(viewModel.items.count))
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
    private func browserOptionsMenu(viewModel: TVBrowserViewModel) -> some View {
        Menu {
            Section(.Strings.galleryMenuLayout) {
                Button {
                    viewModel.setLayout(.grid)
                } label: {
                    Label(
                        String(localized: .Strings.tvMediaViewGrid),
                        systemImage: viewModel.selectedLayout == .grid ? "checkmark" : "square.grid.2x2"
                    )
                }

                Button {
                    viewModel.setLayout(.list)
                } label: {
                    Label(
                        String(localized: .Strings.tvMediaViewList),
                        systemImage: viewModel.selectedLayout == .list ? "checkmark" : "list.bullet"
                    )
                }
            }

            Section(.Strings.galleryMenuSortBy) {
                ForEach(orderedSortKeys, id: \.self) { key in
                    Button {
                        viewModel.applySort(key: key)
                    } label: {
                        Label(
                            key.displayTitle,
                            systemImage: viewModel.selectedSortKey == key ? "checkmark" : "arrow.up.arrow.down"
                        )
                    }
                }
            }

            Section {
                Button {
                    viewModel.toggleSortOrder()
                } label: {
                    Label(
                        viewModel.selectedSortOrder == .ascending
                            ? String(localized: .Strings.tvSortOrderAscendingToggle)
                            : String(localized: .Strings.tvSortOrderDescendingToggle),
                        systemImage: viewModel.selectedSortOrder == .ascending ? "arrow.up" : "arrow.down"
                    )
                }
            }
        } label: {
            Label(
                String(localized: .Strings.tvBrowserMenuOptions),
                systemImage: "ellipsis.circle"
            )
        }
        .buttonStyle(TVControlButtonStyle(isSelected: false))
        .focused($focusedTarget, equals: .optionsMenu)
        .accessibilityLabel(Text(.Strings.tvBrowserMenuOptions))
        .accessibilityIdentifier("browser_options_menu")
    }

    private var orderedSortKeys: [MediaSortKey] {
        [MediaSortKey.name, .date, .size, .type, .kind, .resolution, .duration].filter { source.supportedSortKeys.contains($0) }
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
            return .videoPlayer(
                item: item,
                context: viewModel.items,
                pagination: viewModel.paginationContext
            )
        }
    }
}
