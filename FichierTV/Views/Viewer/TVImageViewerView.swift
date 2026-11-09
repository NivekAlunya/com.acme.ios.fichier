//
//  TVImageViewerView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Full-screen tvOS Image Viewer adhering strictly to Siri Remote navigation rules (Section 5).
///
/// Remote interactions:
/// - **Left / Right**: Navigates to previous / next image.
/// - **Up / Down**: Reveals / hides overlay controls.
/// - **Select**: Toggles overlay visibility.
/// - **Play / Pause**: Starts / stops automated slideshow.
/// - **Menu**: Closes overlay if open, otherwise dismisses viewer back to browser without exiting the app.
public struct TVImageViewerView: View {
    public let initialItem: MediaSourceItem
    public let items: [MediaSourceItem]
    public let paginationContext: TVViewerPaginationContext?

    @State private var viewModel: TVImageViewerViewModel
    @FocusState private var isViewerFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        initialItem: MediaSourceItem,
        items: [MediaSourceItem],
        paginationContext: TVViewerPaginationContext? = nil
    ) {
        self.initialItem = initialItem
        self.items = items
        self.paginationContext = paginationContext
        _viewModel = State(
            wrappedValue: TVImageViewerViewModel(
                initialItem: initialItem,
                items: items,
                paginationContext: paginationContext
            )
        )
    }

    init(viewModel: TVImageViewerViewModel, paginationContext: TVViewerPaginationContext? = nil) {
        self.initialItem = viewModel.currentItem
        self.items = viewModel.items
        self.paginationContext = paginationContext
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            imageCanvas
                .id(viewModel.currentIndex)
                .transition(imageTransition)

            if !viewModel.showOverlay {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy) {
                        viewModel.setOverlayVisible(true)
                    }
                } label: {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TVTransparentFocusButtonStyle())
                .focused($isViewerFocused)
                .accessibilityLabel("Show image viewer controls")
                .onMoveCommand { direction in
                    switch direction {
                    case .left:
                        viewModel.showPrevious()
                    case .right:
                        viewModel.showNext()
                    case .up:
                        withAnimation(reduceMotion ? nil : .snappy) {
                            viewModel.setOverlayVisible(true)
                        }
                    case .down:
                        withAnimation(reduceMotion ? nil : .snappy) {
                            viewModel.setOverlayVisible(false)
                        }
                    default:
                        break
                    }
                }
            }

            if viewModel.isLoadingImage || viewModel.isLoadingMoreImages {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if viewModel.showOverlay {
                TVImageViewerOverlayView(
                    title: viewModel.currentItem.name,
                    currentIndex: viewModel.currentIndex,
                    totalCount: viewModel.items.count,
                    isSlideshowPlaying: viewModel.isSlideshowPlaying,
                    isSettingsSheetPresented: viewModel.isShowingSettingsSheet,
                    canNavigatePrevious: viewModel.canNavigatePrevious,
                    canNavigateNext: viewModel.canNavigateNext,
                    onPrevious: { viewModel.showPrevious() },
                    onToggleSlideshow: { viewModel.toggleSlideshow() },
                    onNext: { viewModel.showNext() },
                    onOpenSettings: { viewModel.isShowingSettingsSheet = true },
                    onClose: { dismiss() }
                )
                .transition(.opacity)
            }
        }
        .onPlayPauseCommand {
            viewModel.toggleSlideshow()
        }
        .onExitCommand {
            if viewModel.showOverlay {
                withAnimation(reduceMotion ? nil : .snappy) {
                    viewModel.setOverlayVisible(false)
                }
            } else {
                dismiss()
            }
        }
        .onChange(of: viewModel.showOverlay) { _, isVisible in
            if !isVisible {
                isViewerFocused = true
                Task { @MainActor in
                    if !viewModel.showOverlay {
                        isViewerFocused = true
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingSettingsSheet) {
            TVSlideshowSettingsView(
                currentInterval: viewModel.slideshowInterval,
                currentStyle: viewModel.transitionStyle,
                onSelectInterval: { interval in
                    viewModel.updateInterval(interval)
                },
                onSelectStyle: { style in
                    viewModel.updateTransitionStyle(style)
                }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            isViewerFocused = true
            await viewModel.loadSettings()
            viewModel.loadCurrentImage()
            await viewModel.prefetchRemainingImagesIfNeeded()
        }
        .onDisappear {
            viewModel.tearDown()
        }
    }

    // MARK: - Canvas & Transitions

    @ViewBuilder
    private var imageCanvas: some View {
        if let image = viewModel.currentImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TVThumbnailView(item: viewModel.currentItem, targetSize: CGSize(width: 800, height: 600))
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var imageTransition: AnyTransition {
        if reduceMotion || viewModel.transitionStyle == .fade {
            return .opacity
        }
        let edgeIn: Edge = (viewModel.transitionDirection == .forward) ? .trailing : .leading
        let edgeOut: Edge = (viewModel.transitionDirection == .forward) ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: edgeIn).combined(with: .opacity),
            removal: .move(edge: edgeOut).combined(with: .opacity)
        )
    }
}
