//
//  VideoPlayerTopBarView.swift
//  fichier
//

import SwiftUI
import AVKit
import FichierKit

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
                    HStack(spacing: 8) {
                        closeButton
                        
                        #if DEBUG
                        debugEngineBadge
                        #endif
                        
                        Spacer()
                        
                        volumeBar
                    }
                    .padding(.horizontal, 16)
                    
                    centerToolsBar
                }
                .padding(.top, 2)
            } else {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        closeButton
                        
                        #if DEBUG
                        debugEngineBadge
                        #endif
                    }
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
    
    #if DEBUG
    /// Debug-only pill badge indicating whether playback is using `AVPlayer` (Native) or `VLCKit` (VLC).
    private var debugEngineBadge: some View {
        let isVLC = controller.engineKind == .extended
        return Text(isVLC ? "VLC" : "NATIVE")
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill((isVLC ? Color.orange : Color.blue).opacity(0.85))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .accessibilityIdentifier("video_player_debug_engine_badge")
    }
    #endif
    
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
    
    /// Contextual quick-jump options computed from the current video duration and playback position.
    private var quickJumpOptions: [VideoQuickJumpOption] {
        VideoQuickJumpOption.buildOptions(
            duration: controller.totalDurationSeconds,
            currentTime: controller.currentPlaybackSeconds
        )
    }
    
    /// Chapters and quick-jump navigation menu matching the tvOS `Chapters & Jump` experience.
    private var chaptersAndJumpMenu: some View {
        let chapters = controller.availableChapters
        let options = quickJumpOptions
        let currentTime = controller.currentPlaybackSeconds
        let duration = controller.totalDurationSeconds
        
        return Menu {
            if !options.isEmpty {
                Section(String(localized: "Quick Jump", comment: "Section header for quick jump options")) {
                    ForEach(options) { option in
                        Button {
                            controller.jumpToTime(option.targetTime)
                        } label: {
                            Text("\(option.label)  (\(VideoQuickJumpOption.formattedTimestamp(option.targetTime)))")
                        }
                    }
                }
            }
            
            if !chapters.isEmpty {
                Section(String(localized: "Chapters", comment: "Section header for video chapters")) {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                        let nextStart = index + 1 < chapters.count ? chapters[index + 1].startTime : duration
                        let isCurrent = currentTime >= chapter.startTime && (nextStart <= chapter.startTime || currentTime < nextStart)
                        Button {
                            controller.jumpToTime(chapter.startTime)
                        } label: {
                            HStack {
                                Text("\(chapter.title)  (\(VideoQuickJumpOption.formattedTimestamp(chapter.startTime)))")
                                if isCurrent {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "list.bullet.rectangle.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Chapters & Quick Jump", comment: "Accessibility label for chapters and quick jump menu"))
        .accessibilityIdentifier("video_player_chapters_jump_menu")
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
                        controller.toggleSubtitles()
                    } label: {
                        Label(
                            controller.trackManager.isSubtitlesEnabled ? String(localized: .Strings.videoPlayerMenuSubtitlesDisable) : String(localized: .Strings.videoPlayerMenuSubtitlesEnable),
                            systemImage: controller.trackManager.isSubtitlesEnabled ? "captions.bubble.fill" : "captions.bubble"
                        )
                    }
                    ForEach(controller.trackManager.availableSubtitles) { option in
                        Button {
                            controller.selectSubtitle(option: option)
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
                            controller.selectAudio(option: option)
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
                .foregroundStyle(Color.white)
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
            
            #if !os(tvOS)
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
            #endif
            
            AirPlayButtonView()
                .frame(width: 30, height: 30)
                .accessibilityLabel(String(localized: "AirPlay", comment: "Accessibility label for AirPlay"))
            
            if !controller.availableChapters.isEmpty || !quickJumpOptions.isEmpty {
                chaptersAndJumpMenu
            }
            
            playbackOptionsMenu
            
            engineSwitchButton
        }
    }
    
    /// Toolbar button switching between native AVPlayer and extended VLCKit playback.
    private var engineSwitchButton: some View {
        let isVLC = controller.engineKind == .extended
        return Button {
            controller.switchEngine()
        } label: {
            Text(isVLC ? "VLC" : "AV")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isVLC ? Color.orange : Color.blue)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.12))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isVLC ? String(localized: "Switch to Native Player", comment: "Accessibility label to switch to native AVPlayer") : String(localized: "Switch to VLC Player", comment: "Accessibility label to switch to VLC player"))
        .accessibilityIdentifier("video_player_switch_engine_button")
    }
}
