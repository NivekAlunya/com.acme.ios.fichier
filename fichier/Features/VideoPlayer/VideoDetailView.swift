//
//  VideoDetailView.swift
//  fichier
//

import SwiftUI
import AVKit

/// Full-screen video detail presentation view hosting custom hardware-accelerated playback.
///
/// ### Core Capabilities
/// - **Controller Lifecycle**: Lazily instantiates `VideoPlayerController` on `.onAppear` and tears down
///   resources on `.onDisappear` (suppressing audio session deactivation if Picture-in-Picture is active).
/// - **Live Subtitles**: Overlays real-time subtitle text segments with adaptive bottom padding that animates
///   cleanly when bottom HUD toolbars appear or fade.
/// - **System Notifications**: Listens for `AVPlayerItem.failedToPlayToEndTimeNotification` for error recovery
///   (while engine `onPlaybackEnded` advances playlists) and `scenePhase` background transitions
///   to flush playback progress to `VideoPlaybackStore`.
/// - **Hardware Keyboard Support**: Complete iPad / Mac shortcuts (`Space`/`K` for play/pause, `J`/`L` for 10s seek,
///   Arrow keys for 5s seek, `[`/`]` for playlist navigation, `M` for mute, Up/Down for volume, `F` for favorite, `Esc` to exit).
public struct VideoDetailView: View {
    /// Shared storage location manager providing media streaming and workers.
    var manager: StorageLocationManager
    
    /// Playlist of video items available for playback.
    let videos: [MediaItem]
    
    /// The initially focused video media item.
    let initialItem: MediaItem
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    /// Central video player controller driving state and playback.
    @State private var controller: VideoPlayerController?
    
    /// Designated public initializer.
    ///
    /// - Parameters:
    ///   - manager: Shared storage location manager.
    ///   - videos: Array of candidate media items (filtered for video types).
    ///   - initialItem: Initial focused video media item.
    public init(
        manager: StorageLocationManager,
        videos: [MediaItem],
        initialItem: MediaItem
    ) {
        self.manager = manager
        let sanitized = videos.filter { $0.isVideo }
        self.videos = sanitized.isEmpty ? [initialItem] : sanitized
        self.initialItem = initialItem
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let controller {
                videoContent(controller: controller)
            }
        }
        .preferredColorScheme(.dark)
        #if !os(tvOS)
        .statusBarHidden(true)
        #endif
        .onAppear {
            if controller == nil {
                controller = VideoPlayerController(
                    manager: manager,
                    videos: videos,
                    initialItem: initialItem
                )
            }
        }
    }
    
    /// Composed video view containing canvas, subtitle overlay, HUD, and lifecycle observers.
    @ViewBuilder
    private func videoContent(controller: VideoPlayerController) -> some View {
        ZStack {
            VideoPlayerCanvasView(controller: controller)
            
            // Active Subtitle Text Overlay
            if !controller.trackManager.currentSubtitleText.isEmpty && controller.trackManager.isSubtitlesEnabled {
                VStack {
                    Spacer()
                    Text(controller.trackManager.currentSubtitleText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                        .padding(.horizontal, 32)
                        .padding(.bottom, controller.showControls ? 56 : 24)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.2), value: controller.showControls)
                }
                .transition(.opacity)
            }
            
            VideoPlayerHUDView(
                controller: controller,
                onDismiss: {
                    controller.tearDownPlayer(deactivateAudioSession: true)
                    dismiss()
                }
            )
        }
        .task(id: controller.currentItem.id) {
            controller.setupPlayer(for: controller.currentItem)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification)) { notification in
            controller.handleItemFailedToPlayToEndTime(notification)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                controller.handleScenePhaseBackground()
            }
        }
        .onDisappear {
            guard !controller.isPiPActive else { return }
            controller.tearDownPlayer(deactivateAudioSession: true)
        }
        #if !os(tvOS)
        .background {
            keyboardShortcuts(controller: controller)
        }
        #endif
    }
    
    // MARK: - Hardware Keyboard Shortcuts
    
    #if !os(tvOS)
    /// Registers hardware keyboard shortcuts for iPad and macOS environments.
    private func keyboardShortcuts(controller: VideoPlayerController) -> some View {
        Group {
            Button("") {
                controller.tearDownPlayer(deactivateAudioSession: true)
                dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])
            
            Button("") { controller.togglePlayPause() }
                .keyboardShortcut(.space, modifiers: [])
            
            Button("") { controller.togglePlayPause() }
                .keyboardShortcut("k", modifiers: [])
            
            Button("") { controller.seekRelative(-5) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            
            Button("") { controller.seekRelative(5) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            
            Button("") { controller.seekRelative(-10) }
                .keyboardShortcut("j", modifiers: [])
            
            Button("") { controller.seekRelative(10) }
                .keyboardShortcut("l", modifiers: [])
            
            Button("") { controller.goToPrevious() }
                .keyboardShortcut("[", modifiers: [])
            
            Button("") { controller.goToNext() }
                .keyboardShortcut("]", modifiers: [])
            
            Button("") { controller.toggleMute() }
                .keyboardShortcut("m", modifiers: [])
            
            Button("") { controller.adjustVolume(by: 0.1) }
                .keyboardShortcut(.upArrow, modifiers: [])
            
            Button("") { controller.adjustVolume(by: -0.1) }
                .keyboardShortcut(.downArrow, modifiers: [])
            
            Button("") { FavoritesManager.shared.toggleFavorite(controller.currentItem) }
                .keyboardShortcut("f", modifiers: [])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
    #endif
}
