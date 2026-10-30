//
//  VideoTrackManager.swift
//  fichier
//

import AVFoundation
import Observation

@Observable
@MainActor
public final class VideoTrackManager {
    public private(set) var availableAudios: [VideoTrackOption] = []
    public private(set) var selectedAudioID: String? = nil
    
    public private(set) var availableSubtitles: [VideoTrackOption] = []
    public private(set) var selectedSubtitleID: String? = nil
    
    public var playbackRate: VideoPlaybackRate = .normal
    
    private var audibleGroup: AVMediaSelectionGroup?
    private var legibleGroup: AVMediaSelectionGroup?
    
    public init() {}
    
    public var hasOptions: Bool {
        availableAudios.count > 1 || !availableSubtitles.isEmpty
    }
    
    public func reset() {
        availableAudios.removeAll()
        selectedAudioID = nil
        availableSubtitles.removeAll()
        selectedSubtitleID = nil
        audibleGroup = nil
        legibleGroup = nil
        playbackRate = .normal
    }
    
    public func loadTracks(for playerItem: AVPlayerItem) async {
        reset()
        
        let asset = playerItem.asset
        
        // 1. Audio Tracks
        if let audioGroup = try? await asset.loadMediaSelectionGroup(for: .audible) {
            self.audibleGroup = audioGroup
            let currentSelection = playerItem.currentMediaSelection.selectedMediaOption(in: audioGroup)
            
            var audioOptions: [VideoTrackOption] = []
            for (idx, option) in audioGroup.options.enumerated() {
                let name = option.displayName.isEmpty ? "Track \(idx + 1)" : option.displayName
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
                let name = option.displayName.isEmpty ? "Subtitle \(idx + 1)" : option.displayName
                let trackID = "sub_\(idx)_\(name)"
                let trackOption = VideoTrackOption(id: trackID, displayName: name, mediaOption: option)
                subOptions.append(trackOption)
                
                if option == currentSelection {
                    selectedSubtitleID = trackID
                }
            }
            self.availableSubtitles = subOptions
            
            // Wake up subtitle renderer if a track is active by default
            if let activeOption = currentSelection {
                playerItem.select(nil, in: subGroup)
                try? await Task.sleep(for: .milliseconds(50))
                playerItem.select(activeOption, in: subGroup)
            }
        }
    }
    
    public var isSubtitlesEnabled: Bool {
        selectedSubtitleID != nil && selectedSubtitleID != "sub_off"
    }
    
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
    
    public func selectAudio(option: VideoTrackOption, in playerItem: AVPlayerItem) {
        guard let group = audibleGroup, let mediaOption = option.mediaOption else { return }
        playerItem.select(mediaOption, in: group)
        selectedAudioID = option.id
    }
    
    public func selectSubtitle(option: VideoTrackOption, in playerItem: AVPlayerItem) {
        guard let group = legibleGroup else { return }
        playerItem.select(option.mediaOption, in: group)
        selectedSubtitleID = option.id
    }
    
    public func setPlaybackRate(_ rate: VideoPlaybackRate, for player: AVPlayer) {
        playbackRate = rate
        player.defaultRate = rate.rawValue
        if player.timeControlStatus == .playing {
            player.rate = rate.rawValue
        }
    }
}
