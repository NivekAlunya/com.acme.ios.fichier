//
//  TVImageViewerOverlayView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Overlay controls HUD for the tvOS Image Viewer, featuring custom focused buttons and blur background.
public struct TVImageViewerOverlayView: View {
    public let title: String
    public let currentIndex: Int
    public let totalCount: Int
    public let isSlideshowPlaying: Bool
    public let isSettingsSheetPresented: Bool
    public let canNavigatePrevious: Bool
    public let canNavigateNext: Bool
    public let initialFocusTarget: TVImageViewerFocusTarget
    public let onFocusChanged: ((TVImageViewerFocusTarget?) -> Void)?
    public let onPrevious: () -> Void
    public let onToggleSlideshow: () -> Void
    public let onNext: () -> Void
    public let onOpenSettings: () -> Void
    public let onClose: () -> Void

    @FocusState private var focusedTarget: TVImageViewerFocusTarget?

    public init(
        title: String,
        currentIndex: Int,
        totalCount: Int,
        isSlideshowPlaying: Bool,
        isSettingsSheetPresented: Bool = false,
        canNavigatePrevious: Bool,
        canNavigateNext: Bool,
        initialFocusTarget: TVImageViewerFocusTarget = .toggleSlideshow,
        onFocusChanged: ((TVImageViewerFocusTarget?) -> Void)? = nil,
        onPrevious: @escaping () -> Void,
        onToggleSlideshow: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.currentIndex = currentIndex
        self.totalCount = totalCount
        self.isSlideshowPlaying = isSlideshowPlaying
        self.isSettingsSheetPresented = isSettingsSheetPresented
        self.canNavigatePrevious = canNavigatePrevious
        self.canNavigateNext = canNavigateNext
        self.initialFocusTarget = initialFocusTarget
        self.onFocusChanged = onFocusChanged
        self.onPrevious = onPrevious
        self.onToggleSlideshow = onToggleSlideshow
        self.onNext = onNext
        self.onOpenSettings = onOpenSettings
        self.onClose = onClose
    }

    public var body: some View {
        VStack {
            topBar
                .frame(maxWidth: .infinity)
                .focusSection()
                .padding(.horizontal, 60)
                .padding(.top, 40)

            Spacer()

            bottomControls
                .frame(maxWidth: .infinity)
                .focusSection()
                .padding(.horizontal, 60)
                .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultFocus($focusedTarget, initialFocusTarget)
        .onAppear {
            focusedTarget = initialFocusTarget
            Task { @MainActor in
                if focusedTarget == nil {
                    focusedTarget = initialFocusTarget
                }
            }
        }
        .onChange(of: focusedTarget) { oldValue, newValue in
            onFocusChanged?(newValue)
            let escapedUpward = (newValue == nil || newValue == .close || newValue == .settings)
            if !canNavigateNext && !isSlideshowPlaying && oldValue == .next && escapedUpward {
                focusedTarget = .toggleSlideshow
            } else if !canNavigatePrevious && oldValue == .previous && escapedUpward {
                focusedTarget = .toggleSlideshow
            }
        }
        .onChange(of: canNavigateNext) { _, canGoNext in
            if !canGoNext && !isSlideshowPlaying && (focusedTarget == .next || focusedTarget == nil) {
                focusedTarget = .toggleSlideshow
            }
        }
        .onChange(of: canNavigatePrevious) { _, canGoPrevious in
            if !canGoPrevious && (focusedTarget == .previous || focusedTarget == nil) {
                focusedTarget = .toggleSlideshow
            }
        }
        .onChange(of: isSettingsSheetPresented) { _, isPresented in
            if !isPresented && focusedTarget == nil {
                focusedTarget = .settings
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.7),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private var topBar: some View {
        HStack(alignment: .center, spacing: 24) {
            Button(action: onClose) {
                Label("Close", systemImage: "xmark")
            }
            .buttonStyle(TVOverlayButtonStyle())
            .focused($focusedTarget, equals: .close)
            .accessibilityLabel("Close viewer")
            .accessibilityIdentifier("image_close_button")

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.white)

                Text("\(currentIndex + 1) of \(totalCount)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            if isSlideshowPlaying {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)

                    Text("Slideshow")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }

            Button(action: onOpenSettings) {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .buttonStyle(TVOverlayButtonStyle())
            .focused($focusedTarget, equals: .settings)
            .accessibilityLabel("Slideshow settings")
            .accessibilityIdentifier("image_settings_button")
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        HStack(spacing: 32) {
            Button(action: onPrevious) {
                Label("Previous", systemImage: "chevron.left")
            }
            .buttonStyle(TVOverlayButtonStyle())
            .focused($focusedTarget, equals: .previous)
            .disabled(!canNavigatePrevious)
            .accessibilityLabel("Previous image")
            .accessibilityIdentifier("image_previous_button")

            Button(action: onToggleSlideshow) {
                Label(
                    isSlideshowPlaying ? "Pause" : "Slideshow",
                    systemImage: isSlideshowPlaying ? "pause.fill" : "play.fill"
                )
            }
            .buttonStyle(TVOverlayButtonStyle())
            .focused($focusedTarget, equals: .toggleSlideshow)
            .accessibilityLabel(isSlideshowPlaying ? "Pause slideshow" : "Start slideshow")
            .accessibilityIdentifier("image_slideshow_button")

            Button(action: onNext) {
                Label("Next", systemImage: "chevron.right")
            }
            .buttonStyle(TVOverlayButtonStyle())
            .focused($focusedTarget, equals: .next)
            .disabled(!canNavigateNext && !isSlideshowPlaying)
            .accessibilityLabel("Next image")
            .accessibilityIdentifier("image_next_button")
        }
    }
}
