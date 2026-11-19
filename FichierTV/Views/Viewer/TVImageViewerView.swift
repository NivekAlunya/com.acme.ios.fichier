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
    @State private var viewModel: TVImageViewerViewModel
    @FocusState private var isViewerFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        initialItem: MediaSourceItem,
        items: [MediaSourceItem],
        paginationContext: TVViewerPaginationContext? = nil
    ) {
        // Note: SwiftUI view structs are transient and re-evaluated during parent updates.
        // While State(wrappedValue:) evaluates on every init, @State retains only the
        // original state object across renders and discards transient allocations.
        _viewModel = State(
            wrappedValue: TVImageViewerViewModel(
                initialItem: initialItem,
                items: items,
                paginationContext: paginationContext
            )
        )
    }

    init(viewModel: TVImageViewerViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .zIndex(0)

            Group {
                if viewModel.transitionStyle == .slide && !reduceMotion {
                    TVSlideCarouselView(
                        items: viewModel.items,
                        currentIndex: viewModel.currentIndex,
                        currentImage: viewModel.currentImage,
                        cachedImage: { viewModel.cachedImage(for: $0) }
                    )
                } else {
                    TVSlideImageView(
                        item: viewModel.currentItem,
                        image: viewModel.currentImage ?? viewModel.cachedImage(for: viewModel.currentItem.id)
                    )
                    .transition(imageTransition)
                    .id(viewModel.currentIndex)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .zIndex(1)

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
                .accessibilityLabel(Text(.Strings.tvImageViewerShowControlsAccessibility))
                .onMoveCommand { direction in
                    switch direction {
                    case .left:
                        withAnimation(slideAnimation) {
                            viewModel.showPrevious()
                        }
                    case .right:
                        withAnimation(slideAnimation) {
                            viewModel.showNext()
                        }
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
                .zIndex(2)
            }

            if viewModel.isLoadingImage && viewModel.currentImage == nil && viewModel.cachedImage(for: viewModel.currentItem.id) == nil {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(5)
            }

            if viewModel.showOverlay {
                let currentFrameSize = viewModel.currentImage.map { "\(Int($0.size.width * $0.scale)) × \(Int($0.size.height * $0.scale))" } ?? MediaDetailStore.shared.cachedDetail(for: viewModel.currentItem.id)
                TVImageViewerOverlayView(
                    title: viewModel.currentItem.name,
                    currentIndex: viewModel.currentIndex,
                    totalCount: viewModel.items.count,
                    isSlideshowPlaying: viewModel.isSlideshowPlaying,
                    isSettingsSheetPresented: viewModel.isShowingSettingsSheet,
                    canNavigatePrevious: viewModel.canNavigatePrevious,
                    canNavigateNext: viewModel.canNavigateNext,
                    frameSize: currentFrameSize,
                    fileSize: viewModel.currentItem.size,
                    onPrevious: {
                        withAnimation(slideAnimation) {
                            viewModel.showPrevious()
                        }
                    },
                    onToggleSlideshow: { viewModel.toggleSlideshow() },
                    onNext: {
                        withAnimation(slideAnimation) {
                            viewModel.showNext()
                        }
                    },
                    onOpenSettings: { viewModel.isShowingSettingsSheet = true },
                    onClose: { dismiss() }
                )
                .transition(.opacity)
                .zIndex(10)
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

    // MARK: - Transitions & Animations

    private var slideAnimation: Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.25)
        }
        if viewModel.isSlideshowPlaying {
            return .easeInOut(duration: 0.8)
        }
        return viewModel.slideAnimation
    }

    private var imageTransition: AnyTransition {
        let baseTransition: AnyTransition
        if reduceMotion {
            baseTransition = .opacity
        } else {
            switch viewModel.transitionStyle {
            case .fade:
                baseTransition = .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 1.04)),
                    removal: .opacity.combined(with: .scale(scale: 0.96))
                )
            case .kenBurns:
                baseTransition = .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 1.08)),
                    removal: .opacity.combined(with: .scale(scale: 0.92))
                )
            case .slide:
                let edgeIn: Edge = (viewModel.transitionDirection == .forward) ? .trailing : .leading
                let edgeOut: Edge = (viewModel.transitionDirection == .forward) ? .leading : .trailing
                baseTransition = .asymmetric(
                    insertion: .move(edge: edgeIn).combined(with: .opacity),
                    removal: .move(edge: edgeOut).combined(with: .opacity)
                )
            }
        }
        return baseTransition.animation(slideAnimation)
    }
}
