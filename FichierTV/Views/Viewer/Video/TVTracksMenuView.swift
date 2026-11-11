//
//  TVTracksMenuView.swift
//  FichierTV
//

import SwiftUI
import FichierKit

/// Sheet dialog presenting available audio streams, subtitle tracks, and playback speed on tvOS.
public struct TVTracksMenuView: View {
    public let audioTracks: [PlayerAudioTrack]
    public let selectedAudio: PlayerAudioTrack?
    public let subtitleTracks: [PlayerSubtitleTrack]
    public let selectedSubtitle: PlayerSubtitleTrack?
    public let playbackRate: TVVideoPlaybackRate
    public let onSelectAudio: (PlayerAudioTrack) -> Void
    public let onSelectSubtitle: (PlayerSubtitleTrack?) -> Void
    public let onSelectPlaybackRate: (TVVideoPlaybackRate) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(
        audioTracks: [PlayerAudioTrack],
        selectedAudio: PlayerAudioTrack?,
        subtitleTracks: [PlayerSubtitleTrack],
        selectedSubtitle: PlayerSubtitleTrack?,
        playbackRate: TVVideoPlaybackRate = .normal,
        onSelectAudio: @escaping (PlayerAudioTrack) -> Void,
        onSelectSubtitle: @escaping (PlayerSubtitleTrack?) -> Void,
        onSelectPlaybackRate: @escaping (TVVideoPlaybackRate) -> Void = { _ in }
    ) {
        self.audioTracks = audioTracks
        self.selectedAudio = selectedAudio
        self.subtitleTracks = subtitleTracks
        self.selectedSubtitle = selectedSubtitle
        self.playbackRate = playbackRate
        self.onSelectAudio = onSelectAudio
        self.onSelectSubtitle = onSelectSubtitle
        self.onSelectPlaybackRate = onSelectPlaybackRate
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Audio") {
                    if audioTracks.isEmpty {
                        Text("Default Audio")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(audioTracks) { track in
                            Button {
                                onSelectAudio(track)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(track.title)
                                    Spacer()
                                    if selectedAudio?.id == track.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Subtitles") {
                    Button {
                        onSelectSubtitle(nil)
                        dismiss()
                    } label: {
                        HStack {
                            Text("Off")
                            Spacer()
                            if selectedSubtitle == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    ForEach(subtitleTracks) { track in
                        Button {
                            onSelectSubtitle(track)
                            dismiss()
                        } label: {
                            HStack {
                                Text(track.title)
                                Spacer()
                                if selectedSubtitle?.id == track.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Section("Playback Speed") {
                    ForEach(TVVideoPlaybackRate.allCases) { rate in
                        Button {
                            onSelectPlaybackRate(rate)
                            dismiss()
                        } label: {
                            HStack {
                                Text(rate.displayName)
                                Spacer()
                                if playbackRate == rate {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Audio & Subtitles")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
