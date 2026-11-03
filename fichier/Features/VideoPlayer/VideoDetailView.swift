//
//  VideoDetailView.swift
//  fichier
//

import SwiftUI
import AVKit

public struct VideoDetailView: View {
    var manager: SMBDirectManager
    let videos: [MediaItem]
    let initialItem: MediaItem
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: VideoPlayerController
    
    public init(
        manager: SMBDirectManager,
        videos: [MediaItem],
        initialItem: MediaItem
    ) {
        self.manager = manager
        self.videos = videos
        self.initialItem = initialItem
        self._controller = State(
            initialValue: VideoPlayerController(
                manager: manager,
                videos: videos,
                initialItem: initialItem
            )
        )
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
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
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .task(id: controller.currentItem.id) {
            controller.setupPlayer(for: controller.currentItem)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { notification in
            controller.handleItemDidPlayToEndTime(notification)
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
        .background {
            keyboardShortcuts
        }
    }
    
    // MARK: - Hardware Keyboard Shortcuts
    
    private var keyboardShortcuts: some View {
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
}
