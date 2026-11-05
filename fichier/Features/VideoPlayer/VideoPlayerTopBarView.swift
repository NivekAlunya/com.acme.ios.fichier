//
//  VideoPlayerTopBarView.swift
//  fichier
//

import SwiftUI
import AVKit

/// Floating top navigation bar for the video player HUD.
///
/// Adapts responsively across device size classes:
/// - In compact portrait: Splits into a two-tier layout (close button & volume bar on top row; center tools bar on bottom row).
/// - In landscape or regular iPad: Renders a single horizontal bar with centered action tools.
///
/// Tool elements include close button, volume slider, previous/next video arrows, favorite toggle,
/// camera roll export, system sharing via `ShareLink`, AirPlay routing, and the playback options menu.
public struct VideoPlayerTopBarView: View {
    /// Active video player controller.
    public var controller: VideoPlayerController
    
    /// Callback invoked to close and dismiss the video player.
    public var onDismiss: () -> Void
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - controller: Active video player controller.
    ///   - onDismiss: Dismissal handler.
    public init(controller: VideoPlayerController, onDismiss: @escaping () -> Void) {
        self.controller = controller
        self.onDismiss = onDismiss
    }
    
    /// True on iPad and Mac regular horizontal size classes.
    private var isRegular: Bool {
        horizontalSizeClass == .regular
    }
    
    /// True on iPhones in vertical portrait orientation.
    private var isCompactPortrait: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }
    
    public var body: some View {
        Group {
            if isCompactPortrait {
                VStack(spacing: 8) {
                    HStack {
                        closeButton
                        
                        Spacer()
                        
                        volumeBar
                    }
                    .padding(.horizontal, 16)
                    
                    centerToolsBar
                }
                .padding(.top, 2)
            } else {
                HStack(spacing: 12) {
                    closeButton
                        .padding(.leading, 16)
                    
                    Spacer(minLength: 8)
                    
                    centerToolsBar
                    
                    Spacer(minLength: 8)
                    
                    volumeBar
                        .padding(.trailing, 16)
                }
                .frame(minHeight: isRegular ? 52 : 44)
                .padding(.top, isRegular ? 6 : 2)
            }
        }
    }
    
    /// Circular dismissal button.
    private var closeButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Close", comment: "Accessibility label to close video player"))
    }
    
    /// Compact volume slider bar bound to controller volume and mute state.
    private var volumeBar: some View {
        @Bindable var bindableController = controller
        return VideoVolumeBar(volume: $bindableController.volume, isMuted: $bindableController.isMuted)
            .onChange(of: controller.volume) { _, newVol in
                controller.setVolume(newVol)
                controller.resetAutoHideTimer()
            }
            .onChange(of: controller.isMuted) { _, muted in
                controller.setMuted(muted)
                controller.resetAutoHideTimer()
            }
    }
    
    /// Previous video button.
    private var previousButton: some View {
        Button {
            controller.goToPrevious()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(controller.videos.count > 1 ? 1 : 0.35))
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(controller.videos.count <= 1)
        .accessibilityLabel(String(localized: "Previous Video", comment: "Accessibility label for previous video"))
    }
    
    /// Next video button.
    private var nextButton: some View {
        Button {
            controller.goToNext()
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(controller.videos.count > 1 ? 1 : 0.35))
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(controller.videos.count <= 1)
        .accessibilityLabel(String(localized: "Next Video", comment: "Accessibility label for next video"))
    }
    
    /// Subtle vertical divider between tool sections.
    private var toolsDivider: some View {
        Divider()
            .frame(height: 20)
            .background(Color.white.opacity(0.3))
    }
    
    /// Floating capsule container hosting action icons.
    private var centerToolsBar: some View {
        HStack(spacing: 6) {
            previousButton
            toolsDivider
            
            actionToolsIcons(spacing: 12)
                .padding(.horizontal, 4)
            
            toolsDivider
            nextButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        )
    }
    
    /// Playback options menu configuring Picture-in-Picture, subtitles, audio tracks, and playback rate.
    private var playbackOptionsMenu: some View {
        Menu {
            Button {
                controller.pipCoordinator.togglePiP()
            } label: {
                Label(
                    controller.isPiPActive ? String(localized: .Strings.videoPlayerMenuPipExit) : String(localized: .Strings.videoPlayerMenuPipEnter),
                    systemImage: controller.isPiPActive ? "pip.exit" : "pip.enter"
                )
            }
            
            if !controller.trackManager.availableSubtitles.isEmpty {
                Section(.Strings.videoPlayerMenuSubtitles) {
                    Button {
                        if let item = controller.player?.currentItem {
                            controller.trackManager.toggleSubtitles(in: item)
                        }
                    } label: {
                        Label(
                            controller.trackManager.isSubtitlesEnabled ? String(localized: .Strings.videoPlayerMenuSubtitlesDisable) : String(localized: .Strings.videoPlayerMenuSubtitlesEnable),
                            systemImage: controller.trackManager.isSubtitlesEnabled ? "captions.bubble.fill" : "captions.bubble"
                        )
                    }
                    ForEach(controller.trackManager.availableSubtitles) { option in
                        Button {
                            if let item = controller.player?.currentItem {
                                controller.trackManager.selectSubtitle(option: option, in: item)
                            }
                        } label: {
                            HStack {
                                Text(option.displayName)
                                if controller.trackManager.selectedSubtitleID == option.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            
            if controller.trackManager.availableAudios.count > 1 {
                Section(.Strings.videoPlayerMenuAudio) {
                    ForEach(controller.trackManager.availableAudios) { option in
                        Button {
                            if let item = controller.player?.currentItem {
                                controller.trackManager.selectAudio(option: option, in: item)
                            }
                        } label: {
                            HStack {
                                Text(option.displayName)
                                if controller.trackManager.selectedAudioID == option.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            
            Section(.Strings.videoPlayerMenuPlaybackSpeed) {
                ForEach(VideoPlaybackRate.allCases) { rate in
                    Button {
                        controller.setPlaybackRate(rate)
                    } label: {
                        HStack {
                            Text(rate.displayName)
                            if controller.trackManager.playbackRate == rate {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(controller.trackManager.isSubtitlesEnabled || controller.trackManager.playbackRate != .normal ? Color.blue : Color.white)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Playback Options", comment: "Accessibility label for playback options menu"))
    }
    
    /// Row of action tool icon buttons.
    @ViewBuilder
    private func actionToolsIcons(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            Button {
                FavoritesManager.shared.toggleFavorite(controller.currentItem)
            } label: {
                Image(systemName: FavoritesManager.shared.isFavorite(controller.currentItem) ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(FavoritesManager.shared.isFavorite(controller.currentItem) ? Color.red : Color.white)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(FavoritesManager.shared.isFavorite(controller.currentItem) ? String(localized: "Remove from Favorites", comment: "Accessibility label to unfavorite") : String(localized: "Add to Favorites", comment: "Accessibility label to favorite"))
            
            if !controller.currentItem.isPhotoAsset {
                Button {
                    controller.saveToCameraRoll()
                } label: {
                    if controller.isSaving {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .disabled(controller.isSaving)
                .accessibilityLabel(String(localized: "Save to Photos", comment: "Accessibility label to save video to Photos"))
            }
            
            if let shareableVideoURL = controller.shareableVideoURL {
                ShareLink(
                    item: shareableVideoURL,
                    preview: SharePreview(controller.currentItem.name)
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Share Video", comment: "Accessibility label to share video"))
            }
            
            AirPlayButtonView()
                .frame(width: 30, height: 30)
                .accessibilityLabel(String(localized: "AirPlay", comment: "Accessibility label for AirPlay"))
            
            playbackOptionsMenu
        }
    }
}
