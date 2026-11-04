//
//  VideoTrackManager.swift
//  fichier
//

import AVFoundation
import Observation

/// Coordinates audio track selection, closed-caption subtitle parsing, and playback rate for `VideoPlayerController`.
///
/// ### Core Responsibilities
/// - Asynchronously loads audible and legible media selection groups from `AVAsset`.
/// - Configures `AVPlayerItemLegibleOutput` with `VideoSubtitleDelegate` to capture subtitle text.
/// - Manages subtitle toggle states and audio track switching on the active `AVPlayerItem`.
/// - Controls playback rate adjustments (`0.5×` through `2.0×`) applied to `AVPlayer`.
@Observable
@MainActor
public final class VideoTrackManager {
    /// Discovered audio tracks available for the current video.
    public private(set) var availableAudios: [VideoTrackOption] = []
    
    /// Unique identifier of the currently selected audio track.
    public private(set) var selectedAudioID: String?
    
    /// Discovered subtitle and closed caption options, including the synthetic "Off" option.
    public private(set) var availableSubtitles: [VideoTrackOption] = []
    
    /// Unique identifier of the currently selected subtitle option.
    public private(set) var selectedSubtitleID: String?
    
    /// Live rendered subtitle string currently visible on screen.
    public var currentSubtitleText: String = ""
    
    /// Active video playback speed multiplier.
    public var playbackRate: VideoPlaybackRate = .normal
    
    private var audibleGroup: AVMediaSelectionGroup?
    private var legibleGroup: AVMediaSelectionGroup?
    private var legibleOutput: AVPlayerItemLegibleOutput?
    private var subtitleDelegate: VideoSubtitleDelegate?
    private weak var loadedPlayerItem: AVPlayerItem?
    
    /// Designated public initializer.
    public init() {}
    
    /// Indicates whether the media item possesses alternative audio streams or subtitle tracks.
    public var hasOptions: Bool {
        availableAudios.count > 1 || !availableSubtitles.isEmpty
    }
    
    /// Resets all loaded track options, disconnecting delegates and outputs.
    public func reset() {
        if let output = legibleOutput {
            loadedPlayerItem?.remove(output)
        }
        loadedPlayerItem = nil
        availableAudios.removeAll()
        selectedAudioID = nil
        availableSubtitles.removeAll()
        selectedSubtitleID = nil
        currentSubtitleText = ""
        audibleGroup = nil
        legibleGroup = nil
        legibleOutput = nil
        subtitleDelegate = nil
    }
    
    /// Asynchronously inspects the player item asset to populate audio and subtitle choices.
    ///
    /// - Parameter playerItem: Active `AVPlayerItem` instance.
    public func loadTracks(for playerItem: AVPlayerItem) async {
        guard loadedPlayerItem !== playerItem else { return }
        reset()
        loadedPlayerItem = playerItem
        
        let asset = playerItem.asset
        
        // 1. Audio Tracks
        if let audioGroup = try? await asset.loadMediaSelectionGroup(for: .audible) {
            guard !Task.isCancelled, loadedPlayerItem === playerItem else { return }
            self.audibleGroup = audioGroup
            let currentSelection = playerItem.currentMediaSelection.selectedMediaOption(in: audioGroup)
            
            var audioOptions: [VideoTrackOption] = []
            for (idx, option) in audioGroup.options.enumerated() {
                let name = option.displayName.isEmpty ? String(localized: .Strings.videoPlayerTrackFallback(idx + 1)) : option.displayName
                let trackID = "audio_\(idx)_\(name)"
                let trackOption = VideoTrackOption(id: trackID, displayName: name, mediaOption: option)
                audioOptions.append(trackOption)
                
                if option == currentSelection || (currentSelection == nil && idx == 0) {
                    selectedAudioID = trackID
                }
            }
            self.availableAudios = audioOptions
        }
        
        // 2. Subtitles Tracks
        if let subGroup = try? await asset.loadMediaSelectionGroup(for: .legible) {
            guard !Task.isCancelled, loadedPlayerItem === playerItem else { return }
            self.legibleGroup = subGroup
            let currentSelection = playerItem.currentMediaSelection.selectedMediaOption(in: subGroup)
            
            var subOptions: [VideoTrackOption] = []
            
            // "Off" option
            let offOption = VideoTrackOption(id: "sub_off", displayName: String(localized: .Strings.videoPlayerSubtitlesOff), mediaOption: nil)
            subOptions.append(offOption)
            
            if currentSelection == nil {
                selectedSubtitleID = "sub_off"
            }
            
            for (idx, option) in subGroup.options.enumerated() {
                let name = option.displayName.isEmpty ? String(localized: .Strings.videoPlayerSubtitleFallback(idx + 1)) : option.displayName
                let trackID = "sub_\(idx)_\(name)"
                let trackOption = VideoTrackOption(id: trackID, displayName: name, mediaOption: option)
                subOptions.append(trackOption)
                
                if option == currentSelection {
                    selectedSubtitleID = trackID
                }
            }
            self.availableSubtitles = subOptions
            
            // Attach legible output to extract text directly
            if !subGroup.options.isEmpty {
                let output = AVPlayerItemLegibleOutput()
                let delegate = VideoSubtitleDelegate { [weak self] text in
                    self?.currentSubtitleText = text
                }
                output.setDelegate(delegate, queue: .main)
                output.suppressesPlayerRendering = false
                self.subtitleDelegate = delegate
                self.legibleOutput = output
                playerItem.add(output)
            }
            
            // Wake up subtitle renderer if a track is active by default
            if let activeOption = currentSelection {
                playerItem.select(nil, in: subGroup)
                try? await Task.sleep(for: .milliseconds(50))
                playerItem.select(activeOption, in: subGroup)
            }
        }
    }
    
    /// Indicates whether a subtitle track is currently enabled.
    public var isSubtitlesEnabled: Bool {
        selectedSubtitleID != nil && selectedSubtitleID != "sub_off"
    }
    
    /// Toggles subtitle state between "Off" and the first available subtitle track.
    ///
    /// - Parameter playerItem: Active `AVPlayerItem`.
    public func toggleSubtitles(in playerItem: AVPlayerItem) {
        if isSubtitlesEnabled {
            if let offOption = availableSubtitles.first(where: { $0.id == "sub_off" }) {
                selectSubtitle(option: offOption, in: playerItem)
            }
        } else {
            if let firstTrack = availableSubtitles.first(where: { $0.id != "sub_off" }) {
                selectSubtitle(option: firstTrack, in: playerItem)
            }
        }
    }
    
    /// Selects an audio stream for the active video.
    ///
    /// - Parameters:
    ///   - option: Chosen audio track option.
    ///   - playerItem: Active `AVPlayerItem`.
    public func selectAudio(option: VideoTrackOption, in playerItem: AVPlayerItem) {
        guard let group = audibleGroup, let mediaOption = option.mediaOption else { return }
        playerItem.select(mediaOption, in: group)
        selectedAudioID = option.id
    }
    
    /// Selects a subtitle stream or disables subtitles.
    ///
    /// - Parameters:
    ///   - option: Chosen subtitle option.
    ///   - playerItem: Active `AVPlayerItem`.
    public func selectSubtitle(option: VideoTrackOption, in playerItem: AVPlayerItem) {
        guard let group = legibleGroup else { return }
        if option.mediaOption == nil {
            currentSubtitleText = ""
        }
        playerItem.select(option.mediaOption, in: group)
        selectedSubtitleID = option.id
    }
    
    /// Configures the playback speed rate on the player.
    ///
    /// - Parameters:
    ///   - rate: Target rate enum.
    ///   - player: Active `AVPlayer`.
    public func setPlaybackRate(_ rate: VideoPlaybackRate, for player: AVPlayer) {
        playbackRate = rate
        player.defaultRate = rate.rawValue
        if player.timeControlStatus == .playing {
            player.rate = rate.rawValue
        }
    }
}
